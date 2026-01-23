"""Processor CLI - generate reading reports"""
import sys
import argparse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path.home() / ".deep-reading"))

from processor.inspectional import generate_inspectional_report, save_report
from db import get_connection

def process_source(source_id: str):
    """Process a source and generate inspectional report"""
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM sources WHERE id = ?",
        (source_id,)
    ).fetchone()

    if not row:
        print(f"Source not found: {source_id}")
        sys.exit(1)

    source = dict(row)
    cache_path = Path(source["cache_path"])
    transcript_path = cache_path / "transcript.txt"

    # Read transcript
    transcript = ""
    if transcript_path.exists():
        transcript = transcript_path.read_text()

    print(f"Generating inspectional report for: {source['title']}")

    # Generate report (without AI for now)
    report = generate_inspectional_report(
        source_id=source_id,
        title=source["title"],
        author=source["author"],
        url=source["url"],
        duration=source["duration"],
        transcript=transcript,
    )

    # Save to Obsidian
    file_path = save_report(source_id, source["title"], report)

    # Update database
    conn.execute("""
        INSERT OR REPLACE INTO notes (source_id, type, title, obsidian_path, status)
        VALUES (?, 'source', ?, ?, 'draft')
    """, (source_id, source["title"], str(file_path)))
    conn.commit()
    conn.close()

    print(f"✓ Report saved to: {file_path}")
    print(f"\nOpen in Obsidian to review and edit.")

def main():
    parser = argparse.ArgumentParser(description="Process content")
    parser.add_argument("source_id", help="Source ID to process")
    args = parser.parse_args()

    process_source(args.source_id)

if __name__ == "__main__":
    main()
