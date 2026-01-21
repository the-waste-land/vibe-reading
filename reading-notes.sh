#!/bin/bash
# Reading notes management script for deep-reading skill
# Supports the new source-based directory structure

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh" 2>/dev/null || {
    # Fallback if config.sh not found
    _deep_reading_get_notes_dir() { echo "$HOME/.claude/skills/deep-reading/notes"; }
    _deep_reading_get_sources_dir() { echo "$(_deep_reading_get_notes_dir)/sources"; }
    _deep_reading_get_themes_dir() { echo "$(_deep_reading_get_notes_dir)/themes"; }
}

NOTES_DIR="$(_deep_reading_get_notes_dir)"
SOURCES_DIR="$(_deep_reading_get_sources_dir)"
THEMES_DIR="$(_deep_reading_get_themes_dir)"
INDEX_FILE="$NOTES_DIR/index.md"

# Ensure directories exist
ensure_dirs() {
    mkdir -p "$NOTES_DIR" "$SOURCES_DIR" "$THEMES_DIR"
}

# List all reading notes
list_notes() {
    ensure_dirs
    echo "=== Reading Notes ==="
    echo "Notes directory: $NOTES_DIR"
    echo ""

    if [[ -d "$SOURCES_DIR" ]]; then
        echo "Sources:"
        find "$SOURCES_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
            local source_name=$(basename "$dir")
            local metadata="$dir/metadata.json"
            local title=""
            local levels=""

            if [[ -f "$metadata" ]]; then
                title=$(grep '"title"' "$metadata" 2>/dev/null | cut -d'"' -f4)
                levels=$(grep '"reading_levels"' "$metadata" 2>/dev/null | cut -d'"' -f4 | tr -d '[],')
            fi

            echo "  [$source_name] ${title:-$source_name} ${levels:+($levels)}"
        done
    fi

    if [[ -d "$THEMES_DIR" ]] && [[ -n "$(ls -A "$THEMES_DIR" 2>/dev/null)" ]]; then
        echo ""
        echo "Themes (Comparative):"
        find "$THEMES_DIR" -name "*.md" -type f | while read -r file; do
            echo "  - $(basename "$file" .md)"
        done
    fi
}

# Search notes by keyword
search_notes() {
    local keyword="$1"
    ensure_dirs
    echo "=== Searching for: $keyword ==="
    echo ""

    local found=0

    echo "Sources:"
    grep -r -i -l "$keyword" "$SOURCES_DIR" 2>/dev/null | while read -r file; do
        echo "  - $file"
        found=1
    done

    echo ""
    echo "Themes:"
    grep -r -i -l "$keyword" "$THEMES_DIR" 2>/dev/null | while read -r file; do
        echo "  - $file"
        found=1
    done

    if [[ $found -eq 0 ]]; then
        echo "No matches found"
    fi
}

# Show note content
show_note() {
    local source_id="$1"
    local level="${2:-inspectional}"  # inspectional, analytical, or transcript

    ensure_dirs
    local source_dir="$SOURCES_DIR/$source_id"

    if [[ ! -d "$source_dir" ]]; then
        echo "Source not found: $source_id"
        echo ""
        echo "Available sources:"
        find "$SOURCES_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
            echo "  - $(basename "$dir")"
        done
        return 1
    fi

    case "$level" in
        inspectional|analytical)
            local file="$source_dir/${level}.md"
            if [[ -f "$file" ]]; then
                cat "$file"
            else
                echo "No ${level} notes found for: $source_id"
                echo "Available files in $source_dir:"
                ls -la "$source_dir"
            fi
            ;;
        metadata)
            if [[ -f "$source_dir/metadata.json" ]]; then
                cat "$source_dir/metadata.json"
            fi
            ;;
        transcript)
            if [[ -f "$source_dir/transcript.txt" ]]; then
                cat "$source_dir/transcript.txt"
            else
                echo "No transcript found for: $source_id"
            fi
            ;;
        all)
            echo "=== Metadata ==="
            if [[ -f "$source_dir/metadata.json" ]]; then
                cat "$source_dir/metadata.json"
            fi
            echo ""
            echo "=== Inspectional ==="
            if [[ -f "$source_dir/inspectional.md" ]]; then
                cat "$source_dir/inspectional.md"
            fi
            echo ""
            echo "=== Analytical ==="
            if [[ -f "$source_dir/analytical.md" ]]; then
                cat "$source_dir/analytical.md"
            fi
            ;;
        *)
            echo "Usage: $0 show <source_id> [level]"
            echo "Levels: inspectional, analytical, metadata, transcript, all"
            ;;
    esac
}

# Update index
update_index() {
    ensure_dirs

    echo "# Reading Notes Index" > "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "## Sources" >> "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "| Source ID | Title | Author | Type | Levels | Tags |" >> "$INDEX_FILE"
    echo "|-----------|-------|--------|------|--------|------|" >> "$INDEX_FILE"

    find "$SOURCES_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
        local source_id=$(basename "$dir")
        local metadata="$dir/metadata.json"

        if [[ -f "$metadata" ]]; then
            # Parse JSON with grep/sed (simple approach)
            local title=$(grep '"title"' "$metadata" 2>/dev/null | sed 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            local author=$(grep '"author"' "$metadata" 2>/dev/null | sed 's/.*"author"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            local type=$(grep '"type"' "$metadata" 2>/dev/null | sed 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            local tags=$(grep '"tags"' "$metadata" 2>/dev/null | sed 's/.*"tags"[[:space:]]*:[[:space:]]*\[.*\].*/\1/' | tr -d '[]"')
            local levels=$(grep '"reading_levels"' "$metadata" 2>/dev/null | sed 's/.*"reading_levels"[[:space:]]*:[[:space:]]*\[.*\].*/\1/' | tr -d '[]"')

            echo "| [$source_id]($dir/) | ${title:-N/A} | ${author:-N/A} | ${type:-N/A} | ${levels:-N/A} | ${tags:-N/A} |" >> "$INDEX_FILE"
        else
            echo "| $source_id | N/A | N/A | N/A | N/A | N/A |" >> "$INDEX_FILE"
        fi
    done

    echo "" >> "$INDEX_FILE"
    echo "## Themes (Comparative Reading)" >> "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "| Theme | Sources |" >> "$INDEX_FILE"
    echo "|-------|---------|" >> "$INDEX_FILE"

    find "$THEMES_DIR" -name "*.md" -type f | sort | while read -r file; do
        local theme_name=$(basename "$file" .md)
        echo "| [$theme_name]($file) | |" >> "$INDEX_FILE"
    done
}

# Show configuration info
show_config() {
    echo "=== Deep Reading Configuration ==="
    echo ""
    echo "Notes directory: $NOTES_DIR"
    echo "Sources directory: $SOURCES_DIR"
    echo "Themes directory: $THEMES_DIR"
    echo ""
    if [[ -n "$DEEP_READING_NOTES_DIR" ]]; then
        echo "Custom notes dir set: DEEP_READING_NOTES_DIR=$DEEP_READING_NOTES_DIR"
    else
        echo "Using default notes directory"
    fi
}

case "${1:-list}" in
    list) list_notes ;;
    search) search_notes "$2" ;;
    show) show_note "$2" "$3" ;;
    update-index) update_index ;;
    config) show_config ;;
    *)
        echo "Usage: $0 {list|search|show|update-index|config}"
        echo ""
        echo "Commands:"
        echo "  list              List all reading notes"
        echo "  search <keyword>  Search notes by keyword"
        echo "  show <source_id>  Show notes for a source"
        echo "                    [level] = inspectional|analytical|metadata|transcript|all"
        echo "  update-index      Update the index.md file"
        echo "  config            Show configuration info"
        ;;
esac
