#!/bin/bash
# YouTube Transcript Fetcher for Deep Reading Skill
# Downloads and processes YouTube video transcripts for analysis
# Uses SQLite database for metadata storage

set -e

NOTES_DIR="${DEEP_READING_NOTES_DIR:-$HOME/.claude/skills/deep-reading/notes}"
DB_FILE="$NOTES_DIR/reading.db"
TEMP_DIR="/tmp/youtube-transcript-$$"

# Create directories
mkdir -p "$NOTES_DIR/sources"
mkdir -p "$NOTES_DIR/themes"
mkdir -p "$TEMP_DIR"

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Initialize database if it doesn't exist
init_db() {
    if [[ ! -f "$DB_FILE" ]]; then
        bash "$NOTES_DIR/../init-db.sh"
    fi
}

# Function to extract video ID from various YouTube URL formats
extract_video_id() {
    local url="$1"
    local video_id=""

    if [[ "$url" =~ youtu\.be/([a-zA-Z0-9_-]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ youtube\.com.*[?]v=([a-zA-Z0-9_-]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ youtube\.com.*\&v=([a-zA-Z0-9_-]+) ]]; then
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

# Function to add source to database
add_source_to_db() {
    local source_id="$1"
    local source_type="$2"
    local url="$3"
    local title="$4"
    local author="$5"
    local duration="$6"
    local file_path="$7"

    local today=$(date '+%Y-%m-%d')

    # Check if source already exists
    local existing=$(sqlite3 "$DB_FILE" "SELECT id FROM sources WHERE id = '$source_id' LIMIT 1")

    if [[ -z "$existing" ]]; then
        sqlite3 "$DB_FILE" << EOSQL
INSERT INTO sources (id, type, url, title, author, duration, file_path, date_added, progress)
VALUES ('$source_id', '$source_type', '$url', '$title', '$author', '$duration', '$file_path', '$today', 'fetched');
EOSQL
        echo "✓ Added to database: $source_id" >&2
    else
        # Update existing source
        sqlite3 "$DB_FILE" << EOSQL
UPDATE sources
SET title = '$title', author = '$author', duration = '$duration', file_path = '$file_path', updated_at = datetime('now')
WHERE id = '$source_id';
EOSQL
        echo "✓ Updated in database: $source_id" >&2
    fi
}

# Function to get source info from database
get_source_info() {
    local source_id="$1"
    sqlite3 "$DB_FILE" "SELECT type, url, title, author, duration, file_path FROM sources WHERE id = '$source_id' LIMIT 1"
}

# Check if yt-dlp is installed
if ! command -v yt-dlp &> /dev/null; then
    echo "Error: yt-dlp is not installed."
    echo ""
    echo "To install:"
    echo "  brew install yt-dlp"
    echo ""
    echo "After installation, run this script again."
    exit 1
fi

# Get YouTube URL
URL="$1"

if [[ -z "$URL" ]]; then
    echo "Usage: $0 <youtube_url>"
    echo ""
    echo "Example:"
    echo "  $0 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'"
    exit 1
fi

# Initialize database
init_db

# Extract video ID
VIDEO_ID=$(extract_video_id "$URL")

if [[ -z "$VIDEO_ID" ]]; then
    echo "Error: Could not extract video ID from URL: $URL"
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

# Change to temp directory for downloads
cd "$TEMP_DIR"

# Try to download subtitles
DOWNLOAD_SUCCESS=false

# Method 1: Auto-generated English
if yt-dlp --skip-download \
          --write-auto-sub \
          --sub-lang "en" \
          --sub-format "vtt" \
          --output "$VIDEO_ID" \
          "$URL" 2>/dev/null; then
    SUB_FILE=$(find "$TEMP_DIR" -name "*.vtt" 2>/dev/null | head -1)
    if [[ -n "$SUB_FILE" && -f "$SUB_FILE" ]]; then
        DOWNLOAD_SUCCESS=true
    fi
fi

# Method 2: Any auto-generated
if [[ "$DOWNLOAD_SUCCESS" != "true" ]]; then
    rm -f "$TEMP_DIR"/*.vtt 2>/dev/null || true
    if yt-dlp --skip-download \
              --write-auto-sub \
              --sub-format "vtt" \
              --output "$VIDEO_ID" \
              "$URL" 2>/dev/null; then
        SUB_FILE=$(find "$TEMP_DIR" -name "*.vtt" 2>/dev/null | head -1)
        if [[ -n "$SUB_FILE" && -f "$SUB_FILE" ]]; then
            DOWNLOAD_SUCCESS=true
        fi
    fi
fi

# Method 3: Manual subtitles
if [[ "$DOWNLOAD_SUCCESS" != "true" ]]; then
    rm -f "$TEMP_DIR"/*.vtt 2>/dev/null || true
    if yt-dlp --skip-download \
              --write-subs \
              --sub-lang "en" \
              --sub-format "vtt" \
              --output "$VIDEO_ID" \
              "$URL" 2>/dev/null; then
        SUB_FILE=$(find "$TEMP_DIR" -name "*.vtt" 2>/dev/null | head -1)
        if [[ -n "$SUB_FILE" && -f "$SUB_FILE" ]]; then
            DOWNLOAD_SUCCESS=true
        fi
    fi
fi

if [[ "$DOWNLOAD_SUCCESS" != "true" || -z "$SUB_FILE" ]]; then
    rmdir "$SOURCE_DIR" 2>/dev/null || true
    echo "Error: Could not fetch transcript for this video."
    echo ""
    echo "Possible reasons:"
    echo "  - Video has no subtitles available"
    echo "  - Video is private or restricted"
    echo "  - Network connectivity issues"
    exit 1
fi

echo "Processing transcript..." >&2

# Get video metadata
VIDEO_TITLE=$(yt-dlp --print "%(title)s" "$URL" 2>/dev/null | sed "s/'/''/g")
VIDEO_CHANNEL=$(yt-dlp --print "%(channel)s" "$URL" 2>/dev/null | sed 's/"/"/g')
VIDEO_DURATION=$(yt-dlp --print "%(duration_string)s" "$URL" 2>/dev/null)

# Escape single quotes for SQL
SAFE_TITLE=$(echo "$VIDEO_TITLE" | sed "s/'/''/g")
SAFE_AUTHOR=$(echo "$VIDEO_CHANNEL" | sed "s/'/''/g")
SAFE_URL=$(echo "$URL" | sed "s/'/''/g")

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

# Add to database
add_source_to_db "$SOURCE_ID" "youtube" "$SAFE_URL" "$SAFE_TITLE" "$SAFE_AUTHOR" "$VIDEO_DURATION" "$SOURCE_DIR/transcript.txt"

echo "" >&2
echo "--- Transcript ---" >&2

# Output the transcript to stdout
cat "$TRANSCRIPT_FILE"
