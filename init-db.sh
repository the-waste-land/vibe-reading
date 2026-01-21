#!/usr/bin/env bash
# Deep Reading SQLite Database Initialization
# Creates the database schema for the Deep Reading skill

set -e

NOTES_DIR="${DEEP_READING_NOTES_DIR:-$HOME/.claude/skills/deep-reading/notes}"
DB_FILE="$NOTES_DIR/reading.db"

# Create notes directory if it doesn't exist
mkdir -p "$NOTES_DIR/sources"
mkdir -p "$NOTES_DIR/themes"

echo "Initializing Deep Reading database: $DB_FILE" >&2

# Create SQLite database with schema
sqlite3 "$DB_FILE" << 'EOSQL'
-- ============================================
-- Deep Reading Notes Database Schema
-- Version: 1.0
-- ============================================

-- Sources table: all reading materials
CREATE TABLE IF NOT EXISTS sources (
    id TEXT PRIMARY KEY,                    -- youtube_KyfUysrNaco, url_example, arxiv_123456
    type TEXT NOT NULL,                     -- youtube, arxiv, url, pdf
    url TEXT,                               -- original URL
    title TEXT NOT NULL,
    author TEXT,
    duration TEXT,                          -- for videos: HH:MM:SS
    file_path TEXT,                         -- path to transcript.txt or pdf
    date_added TEXT NOT NULL,               -- ISO date
    date_read TEXT,                         -- ISO date when actually read
    progress TEXT DEFAULT 'fetched',        -- fetched, inspectional, analytical, complete
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Tags table: flexible tagging system
CREATE TABLE IF NOT EXISTS tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id TEXT NOT NULL,
    tag TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE,
    UNIQUE(source_id, tag)
);

-- Backlinks table: [[wikilink]] support
CREATE TABLE IF NOT EXISTS backlinks (
    source_id TEXT NOT NULL,                 -- where the link comes from
    target_id TEXT NOT NULL,                 -- what is being linked to
    context TEXT,                            -- surrounding text for context
    link_type TEXT DEFAULT 'wiki',           -- wiki, http, mention
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE,
    FOREIGN KEY (target_id) REFERENCES sources(id) ON DELETE CASCADE,
    UNIQUE(source_id, target_id)
);

-- Notes table: reading notes at different levels
CREATE TABLE IF NOT EXISTS notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id TEXT NOT NULL,
    level TEXT NOT NULL,                     -- inspectional, analytical, comparative
    content TEXT,                            -- markdown content
    word_count INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE
);

-- Full-text search on sources and notes
CREATE VIRTUAL TABLE IF NOT EXISTS sources_fts USING fts5(
    title,
    author,
    content,
    content='sources',
    content_rowid='rowid'
);

CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
    content,
    content='notes',
    content_rowid='rowid'
);

-- Triggers to keep FTS tables in sync
CREATE TRIGGER IF NOT EXISTS sources_fts_insert AFTER INSERT ON sources BEGIN
    INSERT INTO sources_fts(rowid, title, author, content)
    VALUES (new.rowid, new.title, new.author, '');
END;

CREATE TRIGGER IF NOT EXISTS sources_fts_delete AFTER DELETE ON sources BEGIN
    DELETE FROM sources_fts WHERE rowid = old.rowid;
END;

CREATE TRIGGER IF NOT EXISTS sources_fts_update AFTER UPDATE ON sources BEGIN
    UPDATE sources_fts SET title = new.title, author = new.author
    WHERE rowid = old.rowid;
END;

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_sources_type ON sources(type);
CREATE INDEX IF NOT EXISTS idx_sources_progress ON sources(progress);
CREATE INDEX IF NOT EXISTS idx_sources_date_added ON sources(date_added);
CREATE INDEX IF NOT EXISTS idx_tags_source ON tags(source_id);
CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag);
CREATE INDEX IF NOT EXISTS idx_backlinks_source ON backlinks(source_id);
CREATE INDEX IF NOT EXISTS idx_backlinks_target ON backlinks(target_id);
CREATE INDEX IF NOT EXISTS idx_notes_source ON notes(source_id);
CREATE INDEX IF NOT EXISTS idx_notes_level ON notes(level);

-- View: all sources with their tags
CREATE VIEW IF NOT EXISTS sources_with_tags AS
SELECT
    s.*,
    GROUP_CONCAT(t.tag, ',') as tags
FROM sources s
LEFT JOIN tags t ON s.id = t.source_id
GROUP BY s.id;

-- View: backlink counts (for graph visualization)
CREATE VIEW IF NOT EXISTS backlink_counts AS
SELECT
    target_id,
    COUNT(*) as count,
    group_concat(source_id, ',') as linked_from
FROM backlinks
GROUP BY target_id;
EOSQL

echo "✓ Database initialized successfully" >&2
echo "" >&2
echo "Schema created:" >&2
echo "  - sources       (reading materials)" >&2
echo "  - tags          (flexible tagging)" >&2
echo "  - backlinks     ([[wikilink]] support)" >&2
echo "  - notes         (reading notes at different levels)" >&2
echo "  - fts tables    (full-text search)" >&2
echo "" >&2
echo "To query the database:" >&2
echo "  sqlite3 \"$DB_FILE\"" >&2
