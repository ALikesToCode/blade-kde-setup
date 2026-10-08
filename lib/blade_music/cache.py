"""The ytm-cache folder: the only place Blade Music writes or deletes audio."""

import datetime as dt
import logging
from pathlib import Path
import re
import subprocess

from .library import Track

log = logging.getLogger("blade-music")
PERMANENT = re.compile(r"private|unavailable|removed|terminated|copyright|not available", re.IGNORECASE)


def download(db, track: Track, settings) -> str | None:
    """Fetch one track with yt-dlp; returns its path relative to the music root."""
    cache = settings["cache_dir"]
    cache.mkdir(parents=True, exist_ok=True)
    command = [
        settings["ytdlp"], f"https://music.youtube.com/watch?v={track.video_id}",
        "--no-playlist", "-f", "bestaudio", "-x",
        "--embed-metadata", "--embed-thumbnail", "--convert-thumbnails", "jpg",
        "--windows-filenames", "--no-overwrites", "--no-progress",
        "--sleep-requests", "1", "--sleep-interval", "2", "--max-sleep-interval", "6",
        "--cookies-from-browser", settings["cookies_from_browser"],
        "-P", str(cache), "-o", "%(artists.0,artist,uploader)s - %(track,title)s [%(id)s].%(ext)s",
        "--print", "after_move:filepath",
    ]
    process = subprocess.run(command, capture_output=True, text=True, timeout=900)
    if process.returncode != 0:
        error = (process.stderr.strip().splitlines() or ["?"])[-1]
        log.warning("download failed %s (%s - %s): %s", track.video_id, track.artist, track.title, error)
        if PERMANENT.search(error):  # private or removed: don't retry every run
            db.execute("INSERT OR REPLACE INTO unavailable VALUES (?, ?, ?)",
                       (track.video_id, error, dt.date.today().isoformat()))
        return None
    path = Path(process.stdout.strip().splitlines()[-1])
    return path.relative_to(settings["music_root"]).as_posix()


def cleanup_allowed(previous_count: int, current_count: int) -> bool:
    """False when the wanted list collapsed, which usually means YouTube changed
    its pages and a list silently came back empty, not that you stopped listening."""
    return current_count >= previous_count / 2


def cleanup(db, settings, today: dt.date, dry_run: bool) -> list[str]:
    """Delete cached downloads that nothing has wanted for keep_days_after_unwanted."""
    cache = settings["cache_dir"].resolve()
    # Files no list has ever claimed (e.g. after the state was reset) start
    # their grace period now instead of counting as long unwanted.
    cached = "SELECT video_id FROM local_files WHERE path LIKE 'ytm-cache/%' AND video_id IS NOT NULL"
    db.execute(f"INSERT OR IGNORE INTO tracks (video_id) {cached}")
    db.execute(f"UPDATE tracks SET last_wanted=? WHERE last_wanted IS NULL AND video_id IN ({cached})",
               (today.isoformat(),))
    cutoff = (today - dt.timedelta(days=settings["keep_days_after_unwanted"])).isoformat()
    rows = db.execute(
        """SELECT f.path FROM local_files f JOIN tracks t USING (video_id)
           WHERE f.path LIKE 'ytm-cache/%' AND t.last_wanted < ?""",
        (cutoff,),
    ).fetchall()
    removed = []
    for (rel,) in rows:
        path = (settings["music_root"] / rel).resolve()
        if cache not in path.parents:  # never touch anything outside ytm-cache
            continue
        log.info("%s unwanted cache file %s", "would remove" if dry_run else "removing", rel)
        if not dry_run:
            path.unlink(missing_ok=True)
            db.execute("DELETE FROM local_files WHERE path=?", (rel,))
        removed.append(rel)
    return removed
