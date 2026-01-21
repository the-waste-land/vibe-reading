#!/bin/bash
# Deep Reading Configuration
# Source this file to set environment variables

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

# Generate source ID from URL or file path
_deep_reading_generate_source_id() {
    local input="$1"
    local source_type="$2"

    case "$source_type" in
        youtube)
            # Extract video ID from various YouTube URL formats
            if [[ "$input" =~ youtu\.be/([a-zA-Z0-9_-]+) ]]; then
                echo "youtube_${BASH_REMATCH[1]}"
            elif [[ "$input" =~ youtube\.com.*[?&]v=([a-zA-Z0-9_-]+) ]]; then
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
export -f _deep_reading_get_notes_dir
export -f _deep_reading_get_sources_dir
export -f _deep_reading_get_themes_dir
export -f _deep_reading_generate_source_id
