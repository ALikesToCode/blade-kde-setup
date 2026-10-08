"""One sync run: gate, fetch the wanted lists, reuse local files, download the rest."""

import datetime as dt
import fcntl
import logging
import subprocess

from . import cache, environment, library, playlists, youtube
from .store import meta_get, meta_set, open_db

log = logging.getLogger("blade-music")


def should_skip(db, settings, now: dt.datetime, force: bool) -> str | None:
    """A reason to skip this run, or None to go ahead."""
    if not environment.mounted(settings["mount_point"]):
        return f"{settings['mount_point']} is not mounted"
    last = meta_get(db, "last_sync")
    gap = dt.timedelta(hours=settings["min_hours_between_syncs"])
    if not force and last and now - dt.datetime.fromisoformat(last) < gap:
        return f"last sync {last}; nothing to do yet (use --force)"
    if not environment.online():
        return "offline"
    return None


def locate(db, wanted: dict[str, library.Track], settings, state_dir, today: dt.date):
    """Split wanted tracks into {video_id: local path} and a download queue."""
    retry_after = (today - dt.timedelta(days=settings["retry_unavailable_days"])).isoformat()
    skip = {v for (v,) in db.execute("SELECT video_id FROM unavailable WHERE day >= ?", (retry_after,))}
    located, fuzzy, missing = {}, [], []
    for track in wanted.values():
        hit = library.find_local(db, track, settings["duration_tolerance"])
        if hit:
            located[track.video_id] = hit[0]
            if hit[1] != "id":
                fuzzy.append(f"{hit[1]}\t{track.video_id}\t{track.artist} - {track.title}\t-> {hit[0]}")
        elif track.video_id not in skip:
            missing.append(track)
    # Matches by tags or filename, for reviewing that none are wrong.
    (state_dir / "fuzzy-matches.tsv").write_text("\n".join(fuzzy) + "\n", encoding="utf-8")
    log.info("wanted %d: %d already local (%d by tags/filename), %d missing, %d unavailable",
             len(wanted), len(located), len(fuzzy), len(missing), len(wanted) - len(located) - len(missing))
    return located, missing


def run(settings, state_dir, force: bool = False, dry_run: bool = False) -> int:
    state_dir.mkdir(parents=True, exist_ok=True)
    lock = open(state_dir / "sync.lock", "w")
    try:  # the hourly timer and the panel's "Sync now" can fire together
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log.info("another sync is running; skipping")
        return 0
    db = open_db(state_dir)
    now = dt.datetime.now()
    reason = should_skip(db, settings, now, force)
    if reason:
        log.info("%s; skipping", reason)
        return 0
    can_download = not (settings["skip_metered"] and environment.metered())
    if not can_download:
        log.info("metered connection: updating lists only, no downloads")

    yt = youtube.client(settings)
    today = now.date()
    library.index_library(db, settings["music_root"])
    lists = youtube.fetch_wanted(db, yt, settings, today)
    wanted: dict[str, library.Track] = {}
    for tracks in lists.values():  # list order = download priority
        for track in tracks:
            wanted.setdefault(track.video_id, track)
    db.executemany("UPDATE tracks SET last_wanted=? WHERE video_id=?", [(today.isoformat(), v) for v in wanted])
    located, missing = locate(db, wanted, settings, state_dir, today)

    budget = settings["max_downloads_per_run"] if can_download and not dry_run else 0
    for track in missing[:budget]:
        rel = cache.download(db, track, settings)
        if rel:
            located[track.video_id] = rel
            log.info("downloaded %s", rel)
    if len(missing) > budget:
        log.info("%d tracks left for later runs", len(missing) - budget)

    library.index_library(db, settings["music_root"])
    if settings["mpd_playlist_dir"]:  # rescan first so MPD knows the new files
        subprocess.run(["mpc", "-q", "--wait", "update"], capture_output=True, timeout=600)
    playlists.write_playlists(settings, lists, located, state_dir)

    previous = int(meta_get(db, "wanted_count") or 0)
    if cache.cleanup_allowed(previous, len(wanted)):
        cache.cleanup(db, settings, today, dry_run)
        if not dry_run:  # only a healthy run becomes the new baseline
            meta_set(db, "wanted_count", str(len(wanted)))
    else:
        log.warning("wanted list shrank from %d to %d; skipping cleanup this run", previous, len(wanted))
    if not dry_run and can_download:
        # A metered run only refreshed lists; let the next unmetered one download.
        meta_set(db, "last_sync", now.isoformat(timespec="seconds"))
    db.commit()
    return 0
