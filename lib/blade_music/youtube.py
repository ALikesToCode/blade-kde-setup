"""Read the wanted lists (liked, own playlists, history, personal mixes) from YouTube Music."""

import datetime as dt
import json
import logging

from .library import Track
from .store import meta_get, meta_set

log = logging.getLogger("blade-music")

# History sections that pin down a day; older ones ("This week", "September")
# only give a rough date.
HISTORY_DAYS = {"Today": 0, "Yesterday": 1}
PERSONAL_MIX_PREFIX = "RDTMAK"


def client(settings):
    """A YTMusic client signed in with the live browser session.

    Reading cookies each run means there is no login file to go stale.
    ytmusicapi only needs the cookie; it derives the Authorization header itself.
    """
    from yt_dlp.cookies import extract_cookies_from_browser
    from ytmusicapi import YTMusic
    from ytmusicapi.auth.browser import setup_browser

    browser, _, profile = settings["cookies_from_browser"].partition(":")
    jar = extract_cookies_from_browser(browser, profile or None)
    # Skip the ST-* page-state cookies the web player piles up while browsing:
    # they can push the header past 60 KB and YouTube answers 413 on paged requests.
    cookies = {c.name: c.value for c in jar
               if c.domain.endswith("youtube.com") and not c.name.startswith("ST-")}
    if "__Secure-3PAPISID" not in cookies:
        raise SystemExit(f"not signed in to YouTube in {settings['cookies_from_browser']}")
    raw = "\n".join([
        "cookie: " + "; ".join(f"{k}={v}" for k, v in cookies.items()),
        f"x-goog-authuser: {settings['auth_user']}",
        "authorization: SAPISIDHASH recomputed-per-request",
    ])
    return YTMusic(json.loads(setup_browser(headers_raw=raw)), user=settings["brand_account"] or None)


def to_track(item: dict, source: str) -> Track | None:
    video_id = item.get("videoId")
    if not video_id:
        return None
    artists = ", ".join(a["name"] for a in item.get("artists") or [] if a.get("name"))
    return Track(video_id, artists, item.get("title") or "", item.get("duration_seconds"), [source])


def play_days(history: list[dict], today: dt.date, first_run: bool) -> list[tuple[str, str]]:
    """(video_id, day) pairs to count; most played = most distinct days played."""
    pairs = []
    for item in history:
        if not item.get("videoId"):
            continue
        offset = HISTORY_DAYS.get(item.get("played"))
        if offset is not None:
            pairs.append((item["videoId"], (today - dt.timedelta(days=offset)).isoformat()))
        elif first_run:
            # Count older sections once so the first list isn't empty, dated so
            # they age out of the window like real plays.
            day = (today - dt.timedelta(days=30)).isoformat()
            pairs.append((item["videoId"], f"{day}:{item.get('played') or '?'}"))
    return pairs


def record_history(db, yt, today: dt.date) -> list[Track]:
    try:
        history = yt.get_history()
    except Exception as e:  # e.g. watch history paused on the account
        log.warning("history unavailable, most-played list won't grow: %s", e)
        return []
    first_run = meta_get(db, "history_backfilled") is None
    db.executemany("INSERT OR IGNORE INTO plays VALUES (?, ?)", play_days(history, today, first_run))
    meta_set(db, "history_backfilled", today.isoformat())
    log.info("history: %d items", len(history))
    return [t for item in history if (t := to_track(item, "history"))]


def top_played(db, settings, today: dt.date, known: dict[str, Track]) -> list[Track]:
    since = (today - dt.timedelta(days=settings["top_window_days"])).isoformat()
    rows = db.execute(
        """SELECT p.video_id, t.artist, t.title, t.duration, COUNT(*) AS n
           FROM plays p LEFT JOIN tracks t USING (video_id)
           WHERE p.day >= ? GROUP BY p.video_id ORDER BY n DESC LIMIT ?""",
        (since, settings["top_count"]),
    ).fetchall()
    out = []
    for video_id, artist, title, duration, _ in rows:
        t = known.get(video_id) or Track(video_id, artist or "", title or "", duration)
        out.append(Track(t.video_id, t.artist, t.title, t.duration, ["top"]))
    return out


def find_mixes(db, yt, titles: list[str], take_all: bool) -> dict[str, str]:
    """{title: playlist ID} for personal mixes on the home page.

    The home page is shuffled per visit and sometimes fails, so IDs seen
    before are remembered and used when none show up.
    """
    remembered = json.loads(meta_get(db, "mix_ids") or "{}")
    try:
        rows = yt.get_home(limit=20)
    except Exception as e:
        log.warning("home page unavailable: %s", e)
        rows = []
    found = {}
    for row in rows:
        for item in row.get("contents") or []:
            title, playlist_id = item.get("title"), item.get("playlistId")
            if not playlist_id or item.get("videoId") or title in found:
                continue
            if title in titles or (take_all and playlist_id.startswith(PERSONAL_MIX_PREFIX)):
                found[title] = playlist_id
    meta_set(db, "mix_ids", json.dumps({**remembered, **found}))
    if not found:
        log.info("no mixes on the home page; using the %d remembered", len(remembered))
        return remembered
    return found


def own_playlists(yt) -> dict[str, str]:
    try:
        playlists = yt.get_library_playlists(limit=100)
    except Exception as e:  # YouTube occasionally returns an empty page
        log.warning("library playlists unavailable this run: %s", e)
        return {}
    # PL... are user playlists; skip auto ones such as Liked Music (LM).
    return {p["title"]: p["playlistId"] for p in playlists if p.get("playlistId", "").startswith("PL")}


def favourite_radios(yt, video_ids: list[str], limit: int) -> dict[str, list[Track]]:
    """{"Like <song>": the song, then its YouTube Music radio} for each favourite."""
    radios = {}
    for video_id in video_ids:
        try:
            items = yt.get_watch_playlist(videoId=video_id, radio=True, limit=limit).get("tracks", [])
        except Exception as e:
            log.warning("could not read the radio for favourite %s: %s", video_id, e)
            continue
        tracks = [t for i in items[:limit + 1] if (t := to_track(i, "favourite"))]
        # The radio normally opens with the song itself; make sure it does.
        seed = [t for t in tracks if t.video_id == video_id]
        tracks = seed[:1] + [t for t in tracks if t.video_id != video_id]
        if tracks:
            title = tracks[0].title if len(tracks[0].title) <= 40 else tracks[0].title[:39] + "…"
            radios[f"Like {title}"] = tracks
    return radios


def fetch_wanted(db, yt, settings, today: dt.date) -> dict[str, list[Track]]:
    """{list name: tracks} in download priority order; refreshes the tracks table."""
    history = record_history(db, yt, today)
    liked = yt.get_liked_songs(limit=settings["liked_limit"]).get("tracks", [])
    lists = {"Liked": [t for i in liked if (t := to_track(i, "liked"))]}
    favourites = favourite_radios(yt, settings["favourites"], settings["favourite_radio_limit"])
    own = own_playlists(yt) if settings["include_own_playlists"] else {}
    mixes = find_mixes(db, yt, settings["mixes"], settings["all_personal_mixes"])
    for name, playlist_id in {**own, **mixes}.items():
        limit = settings["own_playlist_limit"] if name in own else settings["mix_limit"]
        try:
            items = yt.get_playlist(playlist_id, limit=limit).get("tracks", [])[:limit]
        except Exception as e:
            log.warning("could not read %s: %s", name, e)
            continue
        lists.setdefault(name, [t for i in items if (t := to_track(i, name))])

    known = {t.video_id: t for tracks in [history, *lists.values(), *favourites.values()] for t in tracks}
    db.executemany(
        "INSERT INTO tracks VALUES (?,?,?,?,?) ON CONFLICT(video_id) DO UPDATE SET "
        "artist=excluded.artist, title=excluded.title, duration=coalesce(excluded.duration, duration)",
        [(t.video_id, t.artist, t.title, t.duration, None) for t in known.values()],
    )
    # Songs you named yourself download before anything else.
    ordered = {"Favourites": [radio[0] for radio in favourites.values()], "Liked": lists["Liked"], **favourites}
    ordered.update((n, lists[n]) for n in own if n in lists)
    ordered["Most played"] = top_played(db, settings, today, known)
    ordered.update((n, lists[n]) for n in mixes if n in lists and n not in ordered)
    for name, tracks in ordered.items():
        log.info("%s: %d tracks", name, len(tracks))
    return ordered
