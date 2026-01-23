"""Fetcher CLI"""
import sys
import argparse
from pathlib import Path

# Add paths
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path.home() / ".deep-reading"))

from fetcher.youtube import fetch_youtube, extract_video_id
from db import get_connection, init_db
from models import SourceType, ProcessingState

def detect_source_type(url: str) -> str:
    """Detect source type from URL"""
    if "youtube.com" in url or "youtu.be" in url:
        return "youtube"
    elif url.endswith(".mp3") or "podcast" in url.lower():
        return "podcast"
    else:
        return "web"

def fetch(url: str):
    """Fetch content from URL"""
    init_db()

    source_type = detect_source_type(url)
    print(f"Detected source type: {source_type}")

    if source_type == "youtube":
        result = fetch_youtube(url)

        # Save to database
        conn = get_connection()
        conn.execute("""
            INSERT OR REPLACE INTO sources
            (id, type, url, title, author, duration, cache_path, processing_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            result["id"],
            source_type,
            url,
            result["metadata"]["title"],
            result["metadata"]["author"],
            result["metadata"]["duration"],
            result["cache_dir"],
            "ready"
        ))
        conn.commit()
        conn.close()

        print(f"\n✓ Downloaded: {result['metadata']['title']}")
        print(f"  ID: {result['id']}")
        print(f"  Duration: {result['metadata']['duration']}s")
        print(f"  Cache: {result['cache_dir']}")
        print(f"\nTo play: dr play {result['id']}")

    else:
        print(f"Source type '{source_type}' not yet implemented")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Fetch content")
    parser.add_argument("url", help="URL to fetch")
    args = parser.parse_args()

    fetch(args.url)

if __name__ == "__main__":
    main()
