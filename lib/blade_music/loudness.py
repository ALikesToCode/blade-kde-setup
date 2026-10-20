"""Loudness tags so MPD plays every cached song at the same level."""

from concurrent.futures import ThreadPoolExecutor
import logging
from pathlib import Path
import re
import subprocess

log = logging.getLogger("blade-music")
TAG = "R128_TRACK_GAIN"
# YouTube Music's own playback level, so songs sound as loud as in the app.
TARGET_LUFS = -14.0
# Quiet songs are raised only until their true peak reaches this, since the
# Opus tag has no peak field for MPD's clipping guard to read.
PEAK_CEILING = -1.0
MAX_BOOST = 12.0  # near-silent tracks would otherwise get their noise raised
# MPD adds 5 dB to R128 gains to reach the ReplayGain reference level.
MPD_R128_OFFSET = 5.0
SUMMARY = re.compile(r"Integrated loudness:\s*I:\s*(-?[\d.]+) LUFS.*True peak:\s*Peak:\s*(-?[\d.]+|-inf) dBFS",
                     re.DOTALL)


def parse_ebur128(stderr: str) -> tuple[float, float] | None:
    """(integrated LUFS, true peak dBFS) from ffmpeg's ebur128 summary."""
    match = SUMMARY.search(stderr)
    return (float(match[1]), float(match[2])) if match else None


def measure(path: Path) -> tuple[float, float] | None:
    command = ["ffmpeg", "-nostats", "-hide_banner", "-i", str(path), "-map", "0:a:0",
               "-af", "ebur128=peak=true", "-f", "null", "-"]
    try:
        # ffmpeg echoes the file's tags, which are not always valid UTF-8.
        process = subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=600)
    except subprocess.TimeoutExpired:
        return None
    return parse_ebur128(process.stderr) if process.returncode == 0 else None


def r128_gain(integrated: float, peak: float) -> int:
    """The R128_TRACK_GAIN value (dB in Q7.8) that brings a song to TARGET_LUFS."""
    gain = min(TARGET_LUFS - integrated, PEAK_CEILING - peak, MAX_BOOST)
    return max(-32768, min(32767, round((gain - MPD_R128_OFFSET) * 256)))


def untagged(cache_dir: Path) -> list[Path]:
    from mutagen.oggopus import OggOpus

    paths = []
    for path in sorted(cache_dir.glob("*.opus")):
        try:
            if TAG not in (OggOpus(path).tags or {}):
                paths.append(path)
        except Exception as error:
            log.warning("cannot read tags of %s: %s", path.name, error)
    return paths


def tag(path: Path) -> bool:
    from mutagen.oggopus import OggOpus

    result = measure(path)
    if result is None:
        log.warning("could not measure loudness of %s", path.name)
        return False
    audio = OggOpus(path)
    audio[TAG] = [str(r128_gain(*result))]
    audio.save()
    log.debug("%s: %.1f LUFS, peak %.1f dBFS", path.name, *result)
    return True


def tag_cache(cache_dir: Path, jobs: int = 2) -> int:
    """Tag every cached Opus song that has no loudness tag yet; returns how many."""
    if not cache_dir.is_dir():
        return 0
    paths = untagged(cache_dir)
    if paths:
        log.info("measuring loudness of %d songs", len(paths))
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        return sum(pool.map(tag, paths))
