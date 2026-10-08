"""Settings for Blade Music, with paths resolved and the browser profile located."""

import os
from pathlib import Path
import re
import tomllib

HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", str(HOME / ".config")))
CONFIG_FILE = CONFIG_DIR / "blade-music.toml"
# One YouTube Music link or video ID per line; each seeds a "Like <song>" radio.
FAVOURITES_FILE = CONFIG_DIR / "blade-music-favourites.txt"
VIDEO_ID = re.compile(r"(?:[?&]v=|youtu\.be/|^)([A-Za-z0-9_-]{11})(?=$|[?&#])")
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", str(HOME / ".local/state"))) / "blade-music"

DEFAULTS = {
    "music_root": "~/storage/music",
    "mount_point": "~/storage",
    # yt-dlp --cookies-from-browser value; "zen" finds the newest Zen profile.
    "cookies_from_browser": "zen",
    "auth_user": 0,  # X-Goog-AuthUser: which signed-in Google account (0 = first)
    "brand_account": "",  # page ID of a brand channel under that account; empty = main channel
    "liked_limit": 1000,
    "top_count": 300,
    "top_window_days": 90,
    "mixes": ["My Supermix", "Replay Mix", "Discover Mix", "New Release Mix", "Archive Mix"],
    "all_personal_mixes": False,  # also themed mixes and "My Mix N"
    "mix_limit": 50,
    "favourite_radio_limit": 50,  # similar songs fetched per favourite
    "include_own_playlists": True,
    "own_playlist_limit": 500,
    "max_downloads_per_run": 50,
    "min_hours_between_syncs": 6,
    "skip_metered": True,
    "keep_days_after_unwanted": 30,
    "retry_unavailable_days": 30,
    "duration_tolerance": 3,
    "mpd_playlist_dir": "~/.local/share/mpd/playlists",
    # The Arch package ships yt-dlp-ejs, which YouTube's JS challenges require.
    "ytdlp": "/usr/bin/yt-dlp",
}
PATH_KEYS = ("music_root", "mount_point", "mpd_playlist_dir")


def newest_zen_profile(root: Path = HOME / ".zen") -> Path | None:
    """The Zen profile whose cookie store changed most recently, i.e. the one in use."""
    stores = sorted(root.glob("*/cookies.sqlite"), key=lambda p: p.stat().st_mtime, reverse=True)
    return stores[0].parent if stores else None


def resolve_cookie_source(value: str) -> str:
    if value == "zen":
        profile = newest_zen_profile()
        if profile is None:
            raise SystemExit("cookies_from_browser = \"zen\" but no Zen profile with cookies was found")
        return f"firefox:{profile}"
    if ":" in value:  # "browser:~/profile" -> expand the profile path
        browser, profile = value.split(":", 1)
        return f"{browser}:{os.path.expanduser(profile)}"
    return value


def video_id_from(text: str) -> str | None:
    """The video ID in a YouTube (Music) link, a youtu.be link, or a bare ID."""
    match = VIDEO_ID.search(text.strip())
    return match.group(1) if match else None


def read_favourites(path: Path = FAVOURITES_FILE) -> list[str]:
    if not path.exists():
        return []
    ids = []
    for line in path.read_text(encoding="utf-8").splitlines():
        video_id = None if line.lstrip().startswith("#") else video_id_from(line)
        if video_id and video_id not in ids:
            ids.append(video_id)
    return ids


def add_favourite(text: str, path: Path = FAVOURITES_FILE) -> str:
    video_id = video_id_from(text)
    if video_id is None:
        raise SystemExit(f"not a YouTube Music link or video ID: {text}")
    if video_id not in read_favourites(path):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as favourites:
            favourites.write(f"https://music.youtube.com/watch?v={video_id}\n")
    return video_id


def load(path: Path = CONFIG_FILE) -> dict:
    settings = dict(DEFAULTS)
    if path.exists():
        settings.update(tomllib.loads(path.read_text(encoding="utf-8")))
    for key in PATH_KEYS:
        settings[key] = Path(os.path.expanduser(settings[key])) if settings[key] else None
    settings["cache_dir"] = settings["music_root"] / "ytm-cache"
    settings["playlist_dir"] = settings["music_root"] / "playlists"
    settings["favourites"] = read_favourites()
    return settings
