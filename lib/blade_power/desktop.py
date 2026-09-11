"""Use PowerDevil for the internal screen and power-profiles-daemon for CPU policy."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

SERVICE = "org.kde.Solid.PowerManagement"
DISPLAY_ROOT = "/org/kde/ScreenBrightness"
DISPLAY_INTERFACE = "org.kde.ScreenBrightness.Display"


def command(*args):
    try:
        result = subprocess.run(args, text=True, capture_output=True, timeout=10, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as error:
        raise RuntimeError(error.stderr.strip() or error.stdout.strip() or str(error)) from error
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(str(error)) from error


def dbus(path, method, *args):
    return command("qdbus6", SERVICE, path, method, *map(str, args))


def internal_displays():
    names = dbus(DISPLAY_ROOT, "org.freedesktop.DBus.Properties.Get", "org.kde.ScreenBrightness", "DisplaysDBusNames")
    displays = []
    for name in names.splitlines():
        if not name.startswith("display") or not name[7:].isdigit():
            continue
        path = f"{DISPLAY_ROOT}/{name}"
        values = dbus(path, "org.freedesktop.DBus.Properties.GetAll", DISPLAY_INTERFACE)
        properties = dict(line.split(": ", 1) for line in values.splitlines() if ": " in line)
        if properties.get("IsInternal") == "true":
            displays.append((path, int(properties["MaxBrightness"])))
    return displays


def apply_policy(policy):
    if policy["brightness_percent"] is None:
        raise RuntimeError("Power source unavailable; no brightness or power profile was changed")
    displays = internal_displays()
    if not displays:
        raise RuntimeError("PowerDevil does not expose an internal display")
    # Apply the power-saving CPU policy even when USB-C is charging slowly.
    command("powerprofilesctl", "set", policy["power_profile"])
    for path, maximum in displays:
        value = max(1, round(maximum * policy["brightness_percent"] / 100))
        dbus(path, f"{DISPLAY_INTERFACE}.SetBrightness", value, 0)
    return {"internal_displays": len(displays), "applied_at": time.time()}


def read_json(path):
    try:
        value = json.loads(Path(path).read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(data, stream, ensure_ascii=False)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
