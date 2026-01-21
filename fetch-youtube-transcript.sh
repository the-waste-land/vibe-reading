#!/bin/bash
# YouTube Transcript Fetcher for Deep Reading Skill
# Downloads and processes YouTube video transcripts for analysis
# Uses SQLite database for metadata storage

set -e

# Get script directory and source config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

NOTES_DIR="$(_deep_reading_get_notes_dir)"
DB_FILE="$(_deep_reading_get_db_file)"
TEMP_DIR="/tmp/youtube-transcript-$$"

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Find yt-dlp binary
YTDLP=$(_deep_reading_find_ytdlp)
if [[ -z "$YTDLP" ]]; then
    echo "Error: yt-dlp is not installed."
    echo ""
    echo "To install:"
    echo "  pip install --user yt-dlp"
    echo ""
    echo "After installation, run this script again."
    exit 1
fi

# Check yt-dlp works
if ! "$YTDLP" --version &>/dev/null; then
    echo "Error: yt-dlp found but not working: $YTDLP" >&2
    exit 1
fi

# Create directories
_deep_reading_ensure_dirs
mkdir -p "$TEMP_DIR"

# Initialize database if it doesn't exist
if [[ ! -f "$DB_FILE" ]]; then
    echo "Database not found. Initializing..." >&2
    _deep_reading_init_db_if_needed
fi

# Function to extract video ID from various YouTube URL formats
extract_video_id() {
    local url="$1"
    local video_id=""

    if [[ "$url" =~ youtu\.be/([a-zA-Z0-9_-]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ youtube\.com.*[?\&]v=([a-zA-Z0-9_-]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ youtube\.com/shorts/([a-zA-Z0-9_-]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ youtube\.com/embed/([a-zA-Z0-9_-]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    fi

    echo "$video_id" | cut -d'&' -f1 | cut -d'?' -f1
}

# Function to clean VTT subtitle file
clean_subtitles() {
    local input_file="$1"

    if [[ ! -f "$input_file" ]]; then
        echo "Error: Subtitle file not found: $input_file" >&2
        return 1
    fi

    cat "$input_file" | \
        sed 's/<[^>]*>//g' | \
        grep -v '^WEBVTT' | \
        grep -v '^Kind:' | \
        grep -v '^Language:' | \
        grep -v '^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | \
        grep -v 'align:' | \
        grep -v '^[[:space:]]*$' | \
        perl -ne 'print unless $seen{$_}++'
}

# Function to add source to database (with proper SQL escaping)
add_source_to_db() {
    local source_id="$1"
    local source_type="$2"
    local url="$3"
    local title="$4"
    local author="$5"
    local duration="$6"
    local file_path="$7"

    local today=$(date '+%Y-%m-%d')

    # Escape strings for SQL
    source_id_sql=$(_deep_reading_sql_escape "$source_id")
    source_type_sql=$(_deep_reading_sql_escape "$source_type")
    url_sql=$(_deep_reading_sql_escape "$url")
    title_sql=$(_deep_reading_sql_escape "$title")
    author_sql=$(_deep_reading_sql_escape "$author")
    duration_sql=$(_deep_reading_sql_escape "$duration")
    file_path_sql=$(_deep_reading_sql_escape "$file_path")

    # Check if source already exists
    local existing=$(sqlite3 "$DB_FILE" "SELECT id FROM sources WHERE id = '$source_id_sql' LIMIT 1")

    if [[ -z "$existing" ]]; then
        sqlite3 "$DB_FILE" << EOSQL
INSERT INTO sources (id, type, url, title, author, duration, file_path, date_added, progress)
VALUES ('$source_id_sql', '$source_type_sql', '$url_sql', '$title_sql', '$author_sql', '$duration_sql', '$file_path_sql', '$today', 'fetched');
EOSQL
        echo "✓ Added to database: $source_id" >&2
    else
        # Update existing source
        sqlite3 "$DB_FILE" << EOSQL
UPDATE sources
SET title = '$title_sql', author = '$author_sql', duration = '$duration_sql', file_path = '$file_path_sql', updated_at = datetime('now')
WHERE id = '$source_id_sql';
EOSQL
        echo "✓ Updated in database: $source_id" >&2
    fi
}

# Get YouTube URL from argument
URL="$1"

if [[ -z "$URL" ]]; then
    echo "Usage: $0 <youtube_url>"
    echo ""
    echo "Example:"
    echo "  $0 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'"
    exit 1
fi

# Extract video ID
VIDEO_ID=$(extract_video_id "$URL")

if [[ -z "$VIDEO_ID" ]]; then
    echo "Error: Could not extract video ID from URL: $URL" >&2
    exit 1
fi

# Create source ID and directory
SOURCE_ID="youtube_${VIDEO_ID}"
SOURCE_DIR="$NOTES_DIR/sources/$SOURCE_ID"
TRANSCRIPT_FILE="$SOURCE_DIR/transcript.txt"

mkdir -p "$SOURCE_DIR"

# Check if transcript already exists
if [[ -f "$TRANSCRIPT_FILE" ]]; then
    echo "Transcript already exists: $TRANSCRIPT_FILE" >&2
    echo "" >&2
    cat "$TRANSCRIPT_FILE"
    exit 0
fi

echo "Fetching transcript for video: $VIDEO_ID" >&2
echo "Using yt-dlp: $YTDLP" >&2

# Change to temp directory for downloads
cd "$TEMP_DIR"

# Try to download subtitles with multiple fallback methods
DOWNLOAD_SUCCESS=false
SUB_FILE=""

# Method 1: Auto-generated English subtitles
echo "Trying auto-generated English subtitles..." >&2
if "$YTDLP" --skip-download \
          --write-auto-sub \
          --sub-lang "en" \
          --sub-format "vtt" \
          --output "$VIDEO_ID" \
          "$URL" 2>/dev/null; then
    SUB_FILE=$(find "$TEMP_DIR" -name "*.vtt" 2>/dev/null | head -1)
    if [[ -n "$SUB_FILE" && -f "$SUB_FILE" ]]; then
        DOWNLOAD_SUCCESS=true
        echo "✓ Found auto-generated English subtitles" >&2
    fi
fi

# Method 2: Any auto-generated subtitles
if [[ "$DOWNLOAD_SUCCESS" != "true" ]]; then
    echo "Trying any auto-generated subtitles..." >&2
    rm -f "$TEMP_DIR"/*.vtt 2>/dev/null || true
    if "$YTDLP" --skip-download \
              --write-auto-sub \
              --sub-format "vtt" \
              --output "$VIDEO_ID" \
              "$URL" 2>/dev/null; then
        SUB_FILE=$(find "$TEMP_DIR" -name "*.vtt" 2>/dev/null | head -1)
        if [[ -n "$SUB_FILE" && -f "$SUB_FILE" ]]; then
            DOWNLOAD_SUCCESS=true
            echo "✓ Found auto-generated subtitles" >&2
        fi
    fi
fi

# Method 3: Manual subtitles
if [[ "$DOWNLOAD_SUCCESS" != "true" ]]; then
    echo "Trying manual subtitles..." >&2
    rm -f "$TEMP_DIR"/*.vtt 2>/dev/null || true
    if "$YTDLP" --skip-download \
              --write-subs \
              --sub-lang "en" \
              --sub-format "vtt" \
              --output "$VIDEO_ID" \
              "$URL" 2>/dev/null; then
        SUB_FILE=$(find "$TEMP_DIR" -name "*.vtt" 2>/dev/null | head -1)
        if [[ -n "$SUB_FILE" && -f "$SUB_FILE" ]]; then
            DOWNLOAD_SUCCESS=true
            echo "✓ Found manual subtitles" >&2
        fi
    fi
fi

if [[ "$DOWNLOAD_SUCCESS" != "true" || -z "$SUB_FILE" ]]; then
    rmdir "$SOURCE_DIR" 2>/dev/null || true
    echo "Error: Could not fetch transcript for this video." >&2
    echo "" >&2
    echo "Possible reasons:" >&2
    echo "  - Video has no subtitles available" >&2
    echo "  - Video is private or restricted" >&2
    echo "  - Network connectivity issues" >&2
    exit 1
fi

echo "Processing transcript..." >&2

# Get video metadata
VIDEO_TITLE=$("$YTDLP" --print "%(title)s" "$URL" 2>/dev/null)
VIDEO_CHANNEL=$("$YTDLP" --print "%(channel)s" "$URL" 2>/dev/null)
VIDEO_DURATION=$("$YTDLP" --print "%(duration_string)s" "$URL" 2>/dev/null)

# Fallback for empty metadata
VIDEO_TITLE=${VIDEO_TITLE:-"Unknown Title"}
VIDEO_CHANNEL=${VIDEO_CHANNEL:-"Unknown Channel"}
VIDEO_DURATION=${VIDEO_DURATION:-"Unknown"}

# Clean the subtitles and save transcript.txt
FETCH_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

{
    echo "# Video Transcript: $VIDEO_TITLE"
    echo ""
    echo "**Video ID:** $VIDEO_ID"
    echo "**Channel:** $VIDEO_CHANNEL"
    echo "**Duration:** $VIDEO_DURATION"
    echo "**URL:** $URL"
    echo "**Fetched:** $FETCH_TIMESTAMP"
    echo ""
    echo "---"
    echo ""
    clean_subtitles "$SUB_FILE"
} > "$TRANSCRIPT_FILE"

# Add to database with proper escaping
add_source_to_db "$SOURCE_ID" "youtube" "$URL" "$VIDEO_TITLE" "$VIDEO_CHANNEL" "$VIDEO_DURATION" "$SOURCE_DIR/transcript.txt"

echo "" >&2
echo "--- Transcript ---" >&2

# Output the transcript to stdout
cat "$TRANSCRIPT_FILE"
