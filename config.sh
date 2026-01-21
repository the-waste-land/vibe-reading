#!/bin/bash
# Deep Reading Configuration
# Source this file to set environment variables

# Script directory (where this config.sh is located)
DEEPREADING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Database file path
_deep_reading_get_db_file() {
    echo "$(_deep_reading_get_notes_dir)/reading.db"
}

# Get notes directory from environment or use default
_deep_reading_get_notes_dir() {
    if [[ -n "$DEEP_READING_NOTES_DIR" ]]; then
        # Expand tilde if present
        echo "${DEEP_READING_NOTES_DIR/#\~/$HOME}"
    else
        echo "$HOME/.claude/skills/deep-reading/notes"
    fi
}

# Get sources directory
_deep_reading_get_sources_dir() {
    echo "$(_deep_reading_get_notes_dir)/sources"
}

# Get themes directory
_deep_reading_get_themes_dir() {
    echo "$(_deep_reading_get_notes_dir)/themes"
}

# Ensure all required directories exist
_deep_reading_ensure_dirs() {
    mkdir -p "$(_deep_reading_get_notes_dir)/sources"
    mkdir -p "$(_deep_reading_get_notes_dir)/themes"
}

# Find yt-dlp binary (handles both PATH and ~/.local/bin)
_deep_reading_find_ytdlp() {
    # First try command -v
    local ytdlp_bin=$(command -v yt-dlp 2>/dev/null)
    if [[ -n "$ytdlp_bin" && -x "$ytdlp_bin" ]]; then
        echo "$ytdlp_bin"
        return 0
    fi

    # Try ~/.local/bin
    local local_bin="$HOME/.local/bin/yt-dlp"
    if [[ -x "$local_bin" ]]; then
        echo "$local_bin"
        return 0
    fi

    # Try common locations
    for path in /usr/local/bin/yt-dlp /usr/bin/yt-dlp; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

# Check SQLite version (requires 3.37+ for FTS5)
_deep_reading_check_sqlite_version() {
    local version=$(sqlite3 -version 2>/dev/null | awk '{print $1}')
    if [[ -z "$version" ]]; then
        echo "Error: sqlite3 not found" >&2
        return 1
    fi

    # Simple version comparison
    local major=$(echo "$version" | cut -d'.' -f1)
    local minor=$(echo "$version" | cut -d'.' -f1,2)

    if [[ "$major" -lt 3 ]] || [[ "$minor" < "3.37" ]]; then
        echo "Error: SQLite 3.37+ required, found $version" >&2
        return 1
    fi

    return 0
}

# Safely escape string for SQL (single quote escaping)
_deep_reading_sql_escape() {
    local str="$1"
    echo "$str" | sed "s/'/''/g"
}

# Run SQL query with proper error handling
_deep_reading_sql_query() {
    local db_file="$1"
    local query="$2"

    if [[ ! -f "$db_file" ]]; then
        echo "Error: Database not found: $db_file" >&2
        return 1
    fi

    sqlite3 "$db_file" "$query" 2>&1
}

# Initialize database if not exists
_deep_reading_init_db_if_needed() {
    local db_file="$(_deep_reading_get_db_file)"

    if [[ ! -f "$db_file" ]]; then
        local init_script="$DEEPREADING_SCRIPT_DIR/init-db.sh"
        if [[ -f "$init_script" ]]; then
            bash "$init_script"
        else
            echo "Error: init-db.sh not found at $init_script" >&2
            return 1
        fi
    fi
}

# Generate source ID from URL or file path
_deep_reading_generate_source_id() {
    local input="$1"
    local source_type="$2"

    case "$source_type" in
        youtube)
            # Extract video ID from various YouTube URL formats
            if [[ "$input" =~ youtu\.be/([a-zA-Z0-9_-]+) ]]; then
                echo "youtube_${BASH_REMATCH[1]}"
            elif [[ "$input" =~ youtube\.com.*[?\&]v=([a-zA-Z0-9_-]+) ]]; then
                echo "youtube_${BASH_REMATCH[1]}"
            elif [[ "$input" =~ youtube\.com/shorts/([a-zA-Z0-9_-]+) ]]; then
                echo "youtube_${BASH_REMATCH[1]}"
            elif [[ "$input" =~ youtube\.com/embed/([a-zA-Z0-9_-]+) ]]; then
                echo "youtube_${BASH_REMATCH[1]}"
            else
                # If we can't parse, use timestamp
                echo "youtube_$(date +%s)"
            fi
            ;;
        arxiv)
            # Extract arXiv ID
            if [[ "$input" =~ arxiv\.org/abs/([0-9]+\.[0-9]+) ]]; then
                echo "arxiv_${BASH_REMATCH[1]}"
            elif [[ "$input" =~ arXiv:([0-9]+\.[0-9]+) ]]; then
                echo "arxiv_${BASH_REMATCH[1]}"
            else
                echo "arxiv_$(date +%s)"
            fi
            ;;
        url)
            # Extract domain and create slug
            local domain=$(echo "$input" | sed -E 's|https?://||' | cut -d'/' -f1)
            local path=$(echo "$input" | sed -E 's|https?://[^/]+/||' | sed 's|/|-|g' | cut -c1-50)
            echo "${domain}_${path}"
            ;;
        local|file)
            # Local file
            local filename=$(basename "$input")
            echo "local_${filename}"
            ;;
        *)
            echo "unknown_$(date +%s)"
            ;;
    esac
}

# Export functions for use in other scripts
export -f _deep_reading_get_db_file
export -f _deep_reading_get_notes_dir
export -f _deep_reading_get_sources_dir
export -f _deep_reading_get_themes_dir
export -f _deep_reading_ensure_dirs
export -f _deep_reading_find_ytdlp
export -f _deep_reading_check_sqlite_version
export -f _deep_reading_sql_escape
export -f _deep_reading_sql_query
export -f _deep_reading_init_db_if_needed
export -f _deep_reading_generate_source_id
