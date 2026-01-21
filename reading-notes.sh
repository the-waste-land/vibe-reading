#!/bin/bash
# Reading notes management script for deep-reading skill
# Uses SQLite database for metadata management

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh" 2>/dev/null || {
    echo "Error: config.sh not found" >&2
    exit 1
}

NOTES_DIR="$(_deep_reading_get_notes_dir)"
DB_FILE="$(_deep_reading_get_db_file)"
SOURCES_DIR="$(_deep_reading_get_sources_dir)"
THEMES_DIR="$(_deep_reading_get_themes_dir)"

# Ensure database exists
ensure_db() {
    if [[ ! -f "$DB_FILE" ]]; then
        echo "Database not found. Initializing..." >&2
        _deep_reading_init_db_if_needed
    fi
}

# Ensure directories exist
ensure_dirs() {
    _deep_reading_ensure_dirs
}

# List all reading notes from database
list_notes() {
    ensure_db
    echo "=== Reading Notes ==="
    echo "Database: $DB_FILE"
    echo ""

    local count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sources" 2>/dev/null || echo "0")

    if [[ "$count" -eq 0 ]]; then
        echo "No sources in database yet."
        echo ""
        echo "Add a source using:"
        echo "  fetch-youtube-transcript.sh <url>"
        return 0
    fi

    echo "Sources ($count total):"
    echo ""

    # Format: ID | Type | Title | Author | Progress | Date Added"
    printf "%-30s %-10s %-40s %-20s %-12s %-12s\n" "ID" "Type" "Title" "Author" "Progress" "Date"
    printf "%s\n" "$(printf '%.0s-' {1..135})"

    sqlite3 -header "$DB_FILE" "SELECT id, type, title, author, progress, date_added FROM sources ORDER BY date_added DESC;" | while IFS='|' read -r id type title author progress date_added; do
        # Truncate long fields
        title=$(echo "$title" | cut -c1-40)
        author=$(echo "$author" | cut -c1-20)
        printf "%-30s %-10s %-40s %-20s %-12s %-12s\n" "$id" "$type" "$title" "${author:-N/A}" "$progress" "${date_added:-N/A}"
    done

    echo ""

    # Show themes
    if [[ -d "$THEMES_DIR" ]] && [[ -n "$(ls -A "$THEMES_DIR" 2>/dev/null)" ]]; then
        echo "Themes (Comparative):"
        find "$THEMES_DIR" -name "*.md" -type f | while read -r file; do
            echo "  - $(basename "$file" .md)"
        done
    fi
}

# Search notes by keyword using FTS
search_notes() {
    local keyword="$1"

    if [[ -z "$keyword" ]]; then
        echo "Usage: $0 search <keyword>" >&2
        return 1
    fi

    ensure_db
    echo "=== Searching for: $keyword ==="
    echo ""

    # Search in sources
    echo "Sources:"
    local found=0
    sqlite3 "$DB_FILE" "SELECT id, title FROM sources WHERE title LIKE '%$keyword%' OR author LIKE '%$keyword%';" 2>/dev/null | while IFS='|' read -r id title; do
        echo "  [$id] $title"
        found=1
    done

    echo ""

    # Search in notes using FTS
    echo "Notes content:"
    sqlite3 "$DB_FILE" "SELECT s.id, s.title FROM notes n JOIN sources s ON s.id = n.source_id WHERE notes_fts MATCH '$keyword';" 2>/dev/null | while IFS='|' read -r id title; do
        echo "  [$id] $title"
        found=1
    done

    if [[ $found -eq 0 ]]; then
        echo "No matches found"
    fi
}

# Show note content
show_note() {
    local source_id="$1"
    local level="${2:-info}"

    if [[ -z "$source_id" ]]; then
        echo "Usage: $0 show <source_id> [info|metadata|notes|all]" >&2
        return 1
    fi

    ensure_db

    # Check if source exists
    local exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sources WHERE id = '$source_id';" 2>/dev/null || echo "0")
    if [[ "$exists" -eq 0 ]]; then
        echo "Source not found: $source_id" >&2
        echo "" >&2
        echo "Available sources:" >&2
        sqlite3 "$DB_FILE" "SELECT id FROM sources;" 2>/dev/null | while read -r id; do
            echo "  - $id" >&2
        done
        return 1
    fi

    case "$level" in
        info|metadata)
            echo "=== Source Info ==="
            sqlite3 -column "$DB_FILE" << EOSQL
.mode column
.headers on
SELECT * FROM sources WHERE id = '$source_id';
EOSQL
            ;;
        tags)
            echo "=== Tags ==="
            sqlite3 -column "$DB_FILE" "SELECT tag FROM tags WHERE source_id = '$source_id';"
            ;;
        notes)
            echo "=== Reading Notes ==="
            sqlite3 "$DB_FILE" "SELECT level, content FROM notes WHERE source_id = '$source_id' ORDER BY level;" | while IFS='|' read -r level content; do
                echo ""
                echo "## $level Reading"
                echo "$content"
            done
            ;;
        all)
            echo "=== Source Info ==="
            sqlite3 -column "$DB_FILE" << EOSQL
.mode column
.headers on
SELECT * FROM sources WHERE id = '$source_id';
EOSQL
            echo ""
            echo "=== Tags ==="
            sqlite3 "$DB_FILE" "SELECT tag FROM tags WHERE source_id = '$source_id';"
            echo ""
            echo "=== Reading Notes ==="
            sqlite3 "$DB_FILE" "SELECT level, content FROM notes WHERE source_id = '$source_id' ORDER BY level;" | while IFS='|' read -r level content; do
                echo ""
                echo "## $level Reading"
                echo "$content"
            done
            ;;
        *)
            echo "Usage: $0 show <source_id> [info|tags|notes|all]" >&2
            return 1
            ;;
    esac
}

# Add a reading note to database
add_note() {
    local source_id="$1"
    local level="$2"  # inspectional, analytical, comparative
    local content_file="$3"

    if [[ -z "$source_id" || -z "$level" || -z "$content_file" ]]; then
        echo "Usage: $0 add-note <source_id> <level> <content_file>" >&2
        return 1
    fi

    ensure_db

    if [[ ! -f "$content_file" ]]; then
        echo "Error: Content file not found: $content_file" >&2
        return 1
    fi

    # Read content and escape for SQL
    local content=$(cat "$content_file" | sed "s/'/''/g")
    local word_count=$(wc -w < "$content_file")

    # Check if note already exists
    local existing=$(sqlite3 "$DB_FILE" "SELECT id FROM notes WHERE source_id = '$source_id' AND level = '$level';" 2>/dev/null)

    if [[ -n "$existing" ]]; then
        # Update existing note
        sqlite3 "$DB_FILE" "UPDATE notes SET content = '$content', word_count = $word_count, updated_at = datetime('now') WHERE source_id = '$source_id' AND level = '$level';"
        echo "✓ Updated $level reading note for: $source_id" >&2
    else
        # Insert new note
        sqlite3 "$DB_FILE" "INSERT INTO notes (source_id, level, content, word_count) VALUES ('$source_id', '$level', '$content', $word_count);"
        echo "✓ Added $level reading note for: $source_id" >&2
    fi

    # Update source progress
    sqlite3 "$DB_FILE" "UPDATE sources SET progress = '$level', updated_at = datetime('now') WHERE id = '$source_id';"
}

# Delete a source and all related data
delete_source() {
    local source_id="$1"

    if [[ -z "$source_id" ]]; then
        echo "Usage: $0 delete <source_id>" >&2
        return 1
    fi

    ensure_db

    # Confirm deletion
    local title=$(sqlite3 "$DB_FILE" "SELECT title FROM sources WHERE id = '$source_id';" 2>/dev/null)
    if [[ -z "$title" ]]; then
        echo "Source not found: $source_id" >&2
        return 1
    fi

    echo "This will delete: $title" >&2
    echo "Are you sure? (yes/no)" >&2
    read -r confirm

    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled." >&2
        return 0
    fi

    # Delete from database (cascade will handle tags, notes, backlinks)
    sqlite3 "$DB_FILE" "DELETE FROM sources WHERE id = '$source_id';"
    echo "✓ Deleted: $source_id" >&2
}

# Update index.md file from database
update_index() {
    ensure_db
    ensure_dirs

    local INDEX_FILE="$NOTES_DIR/index.md"

    echo "# Reading Notes Index" > "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "## Sources" >> "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "| ID | Type | Title | Author | Progress | Date Added |" >> "$INDEX_FILE"
    echo "|----|------|-------|--------|----------|------------|" >> "$INDEX_FILE"

    sqlite3 "$DB_FILE" "SELECT id, type, title, author, progress, date_added FROM sources ORDER BY date_added DESC;" 2>/dev/null | while IFS='|' read -r id type title author progress date_added; do
        # Escape pipes in title/author
        title=$(echo "$title" | sed 's/|/\\|/g')
        author=$(echo "${author:-N/A}" | sed 's/|/\\|/g')
        progress=${progress:-N/A}
        date_added=${date_added:-N/A}
        echo "| [$id](sources/$id/) | $type | $title | $author | $progress | $date_added |" >> "$INDEX_FILE"
    done

    echo "" >> "$INDEX_FILE"
    echo "## Themes (Comparative Reading)" >> "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"

    if [[ -d "$THEMES_DIR" ]]; then
        find "$THEMES_DIR" -name "*.md" -type f | sort | while read -r file; do
            local theme_name=$(basename "$file" .md)
            echo "- [$theme_name](themes/$theme_name.md)" >> "$INDEX_FILE"
        done
    fi

    echo "✓ Index updated: $INDEX_FILE" >&2
}

# Show configuration info
show_config() {
    echo "=== Deep Reading Configuration ==="
    echo ""
    echo "Script directory: $SCRIPT_DIR"
    echo "Notes directory: $NOTES_DIR"
    echo "Database: $DB_FILE"
    echo "Sources directory: $SOURCES_DIR"
    echo "Themes directory: $THEMES_DIR"
    echo ""

    # Check yt-dlp
    local ytdlp=$(_deep_reading_find_ytdlp)
    if [[ -n "$ytdlp" ]]; then
        echo "yt-dlp: $ytdlp"
        local version=$("$ytdlp" --version 2>/dev/null)
        echo "  version: $version"
    else
        echo "yt-dlp: NOT FOUND"
    fi
    echo ""

    # Check SQLite
    local sqlite_version=$(sqlite3 -version 2>/dev/null | awk '{print $1}')
    echo "SQLite: $sqlite_version"
    echo ""

    if [[ -n "$DEEP_READING_NOTES_DIR" ]]; then
        echo "Custom notes dir: DEEP_READING_NOTES_DIR=$DEEP_READING_NOTES_DIR"
    else
        echo "Using default notes directory"
    fi
}

# Show statistics
show_stats() {
    ensure_db

    echo "=== Deep Reading Statistics ==="
    echo ""

    local total_sources=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sources;" 2>/dev/null || echo "0")
    local total_notes=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM notes;" 2>/dev/null || echo "0")
    local total_tags=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tags;" 2>/dev/null || echo "0")

    echo "Total sources: $total_sources"
    echo "Total reading notes: $total_notes"
    echo "Total tags: $total_tags"
    echo ""

    echo "By type:"
    sqlite3 "$DB_FILE" "SELECT type, COUNT(*) as count FROM sources GROUP BY type;" 2>/dev/null | while IFS='|' read -r type count; do
        echo "  $type: $count"
    done
    echo ""

    echo "By progress:"
    sqlite3 "$DB_FILE" "SELECT progress, COUNT(*) as count FROM sources GROUP BY progress;" 2>/dev/null | while IFS='|' read -r progress count; do
        echo "  $progress: $count"
    done
}

# Main command dispatcher
case "${1:-list}" in
    list) list_notes ;;
    search) search_notes "$2" ;;
    show) show_note "$2" "$3" ;;
    add-note) add_note "$2" "$3" "$4" ;;
    delete) delete_source "$2" ;;
    update-index) update_index ;;
    config) show_config ;;
    stats) show_stats ;;
    *)
        echo "Usage: $0 {list|search|show|add-note|delete|update-index|config|stats}"
        echo ""
        echo "Commands:"
        echo "  list              List all reading notes"
        echo "  search <keyword>  Search notes by keyword"
        echo "  show <source_id>  Show details for a source"
        echo "                    [level] = info|tags|notes|all"
        echo "  add-note <id> <level> <file>  Add a reading note from file"
        echo "  delete <source_id>  Delete a source and its notes"
        echo "  update-index      Update the index.md file"
        echo "  config            Show configuration info"
        echo "  stats             Show statistics"
        ;;
esac
