"""Command-line entry points for Blade Music."""

import argparse
import json
import logging
import sqlite3
import subprocess
import sys

from . import config, environment, library, sync
from .store import meta_get, open_db

SYNC_NOW_UNIT = "blade-music-sync-now.service"
SYNC_UNITS = ("blade-music-sync.service", SYNC_NOW_UNIT)


def _output(*command: str) -> str:
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def status(settings) -> dict:
    """Everything the panel widget shows, in one cheap call."""
    database = config.STATE_DIR / "state.db"
    summary = config.STATE_DIR / "playlists.json"
    cache_dir = settings["cache_dir"]
    states = set(_output("systemctl", "--user", "is-active", *SYNC_UNITS).split())
    return {
        "last_sync": meta_get(sqlite3.connect(database), "last_sync") if database.exists() else None,
        # A running oneshot unit reports "activating".
        "syncing": bool({"active", "activating"} & states),
        "mounted": environment.mounted(settings["mount_point"]),
        "cached": sum(1 for _ in cache_dir.glob("*.*")) if cache_dir.is_dir() else 0,
        "current": _output("mpc", "current", "-f", "[%artist% - ]%title%|%file%"),
        "state": _output("mpc", "status", "%state%") or "stopped",
        "playlists": json.loads(summary.read_text(encoding="utf-8")) if summary.exists() else [],
    }


def play(playlist: str | None) -> int:
    """Replace the queue with a stored playlist, or the shuffled library, and play."""
    steps = [["mpc", "-q", "clear"]]
    steps += [["mpc", "-q", "load", playlist]] if playlist else [["mpc", "-q", "add", "/"], ["mpc", "-q", "shuffle"]]
    steps += [["mpc", "-q", "play"]]
    for step in steps:
        result = subprocess.run(step, capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stderr.strip() or f"{' '.join(step)} failed", file=sys.stderr)
            return 1
    return 0


def run() -> None:
    parser = argparse.ArgumentParser(description="Keep an offline copy of the YouTube Music you listen to.")
    parser.add_argument("-v", "--verbose", action="store_true")
    commands = parser.add_subparsers(dest="command", required=True)
    sync_parser = commands.add_parser("sync", help="fetch lists, reuse local files, download the rest")
    sync_parser.add_argument("--force", action="store_true", help="ignore min_hours_between_syncs")
    sync_parser.add_argument("--dry-run", action="store_true", help="no downloads or deletions")
    commands.add_parser("sync-now", help="start a forced sync in the background")
    commands.add_parser("index", help="scan the music folder")
    commands.add_parser("status", help="JSON status for the panel widget")
    play_parser = commands.add_parser("play", help="play a stored playlist, or the whole library shuffled")
    play_parser.add_argument("playlist", nargs="?", help="MPD playlist name; omit for the whole library")
    favourite_parser = commands.add_parser("favourite", help="songs whose radio of similar songs is cached")
    favourite_parser.add_argument("link", nargs="?", help="YouTube Music link or video ID to add; omit to list")
    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
    settings = config.load()

    if args.command == "sync":
        settings["cookies_from_browser"] = config.resolve_cookie_source(settings["cookies_from_browser"])
        sys.exit(sync.run(settings, config.STATE_DIR, force=args.force, dry_run=args.dry_run))
    if args.command == "sync-now":
        sys.exit(subprocess.run(["systemctl", "--user", "start", "--no-block", SYNC_NOW_UNIT]).returncode)
    if args.command == "index":
        db = open_db(config.STATE_DIR)
        library.index_library(db, settings["music_root"])
        total, with_id, tagged = db.execute(
            "SELECT COUNT(*), COUNT(video_id), SUM(key_tags != '') FROM local_files").fetchone()
        print(f"{total} files indexed: {with_id} with a YouTube ID, {tagged} tagged, "
              f"{total - (tagged or 0)} matched by filename only")
        return
    if args.command == "favourite":
        if args.link:
            print(f"added {config.add_favourite(args.link)}; run blade-music sync-now to fetch similar songs")
        for video_id in config.read_favourites():
            print(f"https://music.youtube.com/watch?v={video_id}")
        return
    if args.command == "status":
        print(json.dumps(status(settings), ensure_ascii=False))
        return
    sys.exit(play(args.playlist))
