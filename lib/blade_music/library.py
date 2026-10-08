"""Index the local music folder and find existing copies of wanted tracks."""

from dataclasses import dataclass, field
import logging
from pathlib import Path
import re
import subprocess
import unicodedata

AUDIO_EXTS = {".flac", ".mp3", ".opus", ".ogg", ".m4a", ".aac", ".wav", ".webm", ".mp4", ".mka"}
# Containers that may hold video; used only when no audio-only copy matches.
VIDEO_EXTS = {".webm", ".mp4"}
ID_IN_NAME = re.compile(r"\[([A-Za-z0-9_-]{11})\]")
NOISE = re.compile(
    r"\((?:official|lyric|lyrics|audio|video|visualizer|music video|hd|hq|4k)[^)]*\)"
    r"|\[(?:official|lyric|lyrics|audio|video|visualizer|music video|hd|hq|4k)[^\]]*\]",
    re.IGNORECASE,
)

log = logging.getLogger("blade-music")


@dataclass
class Track:
    video_id: str
    artist: str
    title: str
    duration: float | None
    sources: list[str] = field(default_factory=list)


def norm(text: str | None) -> str:
    if not text:
        return ""
    text = unicodedata.normalize("NFKC", text)
    text = ID_IN_NAME.sub(" ", text)
    text = NOISE.sub(" ", text)
    text = text.casefold()
    # Keep letters/digits from any script (CJK titles), drop punctuation.
    text = "".join(ch if ch.isalnum() else " " for ch in text)
    return " ".join(text.split())


def tag_key(artist: str | None, title: str | None) -> str:
    return f"{norm(artist)}|{norm(title)}" if artist and title else ""


def probe(path: Path) -> tuple[str | None, str | None, float | None]:
    import mutagen

    try:
        audio = mutagen.File(path, easy=True)
    except Exception:
        audio = None
    if audio is not None:
        tags = audio.tags or {}
        first = lambda key: (tags.get(key) or [None])[0]
        return first("artist"), first("title"), getattr(audio.info, "length", None)
    # mutagen can't read .webm; fall back to ffprobe for the duration.
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
            capture_output=True, text=True, timeout=20,
        ).stdout.strip()
        return None, None, float(out) if out else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None, None, None


def index_library(db, root: Path) -> int:
    """Refresh the index incrementally (by mtime and size); returns the file count."""
    seen, changed = set(), 0
    known = {p: (m, s) for p, m, s in db.execute("SELECT path, mtime, size FROM local_files")}
    for path in root.rglob("*"):
        if path.suffix.lower() not in AUDIO_EXTS or not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        seen.add(rel)
        st = path.stat()
        if known.get(rel) == (st.st_mtime, st.st_size):
            continue
        artist, title, duration = probe(path)
        match = ID_IN_NAME.search(path.name)
        db.execute(
            "INSERT OR REPLACE INTO local_files VALUES (?,?,?,?,?,?,?,?,?)",
            (rel, st.st_mtime, st.st_size, match.group(1) if match else None, artist, title,
             duration, tag_key(artist, title), norm(path.stem)),
        )
        changed += 1
    gone = set(known) - seen
    db.executemany("DELETE FROM local_files WHERE path=?", [(p,) for p in gone])
    db.commit()
    log.info("index: %d files, %d updated, %d removed", len(seen), changed, len(gone))
    return len(seen)


def _rank(rel: str) -> int:
    # Prefer audio-only files over video containers, originals over the cache.
    return (Path(rel).suffix.lower() in VIDEO_EXTS) * 2 + rel.startswith("ytm-cache/")


def find_local(db, track: Track, tolerance: float) -> tuple[str, str] | None:
    """Return (path relative to the music root, how it matched) or None.

    A YouTube ID in the filename is trusted outright. Otherwise artist/title
    tags must match, or for untagged files the filename must; both also need
    the lengths to agree, so a different recording of the same song is fetched.
    """
    rows = db.execute("SELECT path FROM local_files WHERE video_id=?", (track.video_id,)).fetchall()
    if rows:
        return min((r[0] for r in rows), key=_rank), "id"

    def close(duration):
        return track.duration is None or duration is None or abs(duration - track.duration) <= tolerance

    key = tag_key(track.artist, track.title)
    if key:
        rows = db.execute("SELECT path, duration FROM local_files WHERE key_tags=?", (key,)).fetchall()
        hits = [p for p, d in rows if close(d)]
        if hits:
            return min(hits, key=_rank), "tags"

    if track.duration is None:
        return None
    names = {norm(track.title), norm(f"{track.artist} - {track.title}"), norm(f"{track.title} - {track.artist}")}
    names.discard("")
    if not names:
        return None
    rows = db.execute(
        f"SELECT path, duration FROM local_files WHERE key_tags='' AND key_name IN ({','.join('?' * len(names))})",
        tuple(names),
    ).fetchall()
    hits = [p for p, d in rows if d is not None and abs(d - track.duration) <= tolerance]
    return (min(hits, key=_rank), "filename") if hits else None
