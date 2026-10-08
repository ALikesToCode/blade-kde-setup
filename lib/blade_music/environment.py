"""Checks that decide whether a sync should run on this laptop right now."""

from pathlib import Path
import subprocess
import urllib.request


def mounted(path: Path) -> bool:
    return subprocess.run(["findmnt", "-M", str(path)], capture_output=True).returncode == 0


def online() -> bool:
    try:
        urllib.request.urlopen(urllib.request.Request("https://music.youtube.com", method="HEAD"), timeout=8)
        return True
    except OSError:
        return False


def metered() -> bool:
    """True when NetworkManager marks an active connection metered (e.g. a hotspot)."""
    try:
        devices = subprocess.run(["nmcli", "-t", "-f", "DEVICE,STATE,TYPE", "dev"],
                                 capture_output=True, text=True, timeout=5).stdout
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False
    for line in devices.splitlines():
        device, state, kind = (line.rsplit(":", 2) + ["", ""])[:3]
        if state != "connected" or kind in {"loopback", "bridge", "tun"}:
            continue
        value = subprocess.run(["nmcli", "-t", "-g", "GENERAL.METERED", "dev", "show", device],
                               capture_output=True, text=True, timeout=5).stdout.strip()
        if value.startswith("yes"):
            return True
    return False
