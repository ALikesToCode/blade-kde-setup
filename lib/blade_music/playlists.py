"""Write the wanted lists as playlists pointing at whichever local copy exists."""

import json
import re
from pathlib import Path

from .library import Track


def safe_name(name: str) -> str:
    return re.sub(r'[<>:"/\\|?*]', "_", name)


def write_playlists(settings, lists: dict[str, list[Track]], located: dict[str, str], state_dir: Path) -> list[dict]:
    """Write .m3u8 files next to the music (for any player) and .m3u files for MPD.

    MPD resolves stored playlists against its music directory, so its copies
    use paths relative to the music root; the others are relative to playlists/.
    Returns the summary the panel widget shows.
    """
    out = settings["playlist_dir"]
    out.mkdir(parents=True, exist_ok=True)
    mpd_dir = settings["mpd_playlist_dir"]
    summary = []
    for name, tracks in lists.items():
        entries = [("#EXTINF:%d,%s - %s" % (int(t.duration or -1), t.artist, t.title), located[t.video_id])
                   for t in tracks if t.video_id in located]
        playlist = f"YTM - {safe_name(name)}"
        portable = ["#EXTM3U"] + [line for info, rel in entries for line in (info, "../" + rel)]
        (out / f"{playlist}.m3u8").write_text("\n".join(portable) + "\n", encoding="utf-8")
        if mpd_dir:
            mpd_dir.mkdir(parents=True, exist_ok=True)
            relative = ["#EXTM3U"] + [line for info, rel in entries for line in (info, rel)]
            (mpd_dir / f"{playlist}.m3u").write_text("\n".join(relative) + "\n", encoding="utf-8")
        summary.append({"name": name, "playlist": playlist, "available": len(entries), "total": len(tracks)})
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "playlists.json").write_text(json.dumps(summary, ensure_ascii=False), encoding="utf-8")
    return summary
