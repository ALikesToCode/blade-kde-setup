"""SQLite state: the local file index, play days, wanted tracks, and run metadata.

Kept under ~/.local/state rather than the music drive: SQLite locking over
ntfs-3g is unreliable.
"""

from pathlib import Path
import sqlite3

SCHEMA = """
CREATE TABLE IF NOT EXISTS local_files (
    path TEXT PRIMARY KEY, mtime REAL, size INTEGER,
    video_id TEXT, artist TEXT, title TEXT, duration REAL,
    key_tags TEXT, key_name TEXT);
CREATE INDEX IF NOT EXISTS local_vid ON local_files(video_id);
CREATE TABLE IF NOT EXISTS plays (
    video_id TEXT, day TEXT, PRIMARY KEY (video_id, day));
CREATE TABLE IF NOT EXISTS tracks (
    video_id TEXT PRIMARY KEY, artist TEXT, title TEXT, duration REAL,
    last_wanted TEXT);
CREATE TABLE IF NOT EXISTS unavailable (
    video_id TEXT PRIMARY KEY, reason TEXT, day TEXT);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
"""


def open_db(state_dir: Path) -> sqlite3.Connection:
    state_dir.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(state_dir / "state.db")
    db.executescript(SCHEMA)
    return db


def meta_get(db: sqlite3.Connection, key: str) -> str | None:
    row = db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return row[0] if row else None


def meta_set(db: sqlite3.Connection, key: str, value: str) -> None:
    db.execute("INSERT OR REPLACE INTO meta VALUES (?, ?)", (key, value))
