"""Pure policy decisions, separate from hardware and desktop operations."""

import configparser
from pathlib import Path

DEFAULTS = {
    "main_brightness": 100,
    "usb_brightness": 40,
    "battery_brightness": 17,
    "low_battery_brightness": 12,
    "low_battery_percent": 15,
}


def load_settings(path):
    parser = configparser.ConfigParser(interpolation=None)
    if Path(path).exists():
        with Path(path).open() as stream:
            parser.read_file(stream)
    settings = dict(DEFAULTS)
    for key, default in settings.items():
        value = parser.getint("brightness", key, fallback=default)
        if not 1 <= value <= 100:
            raise ValueError(f"{key} must be between 1 and 100")
        settings[key] = value
    return settings


def decide(telemetry, selection, settings):
    detected = telemetry["detected"]
    external = detected in ("external", "usb")
    selected = selection if external and selection in ("main", "usb") else "auto"
    source = selected if selected != "auto" else detected
    capacities = [b["capacity"] for b in telemetry["batteries"] if b["capacity"] is not None]
    low = bool(capacities) and min(capacities) <= settings["low_battery_percent"]
    labels = {
        "main": "400 W main charger (selected)",
        "usb": "USB-C charger (selected)" if selected == "usb" else "USB-C power (detected)",
        "external": "External power — charger type unknown",
        "battery": "Low battery" if low else "Battery",
        "unavailable": "Power source unavailable",
    }
    brightness_key = "low_battery" if source == "battery" and low else source
    if source == "external":
        brightness_key = "usb"
    brightness = settings.get(f"{brightness_key}_brightness")
    warning = ""
    if source == "external":
        warning = "Firmware does not identify the charger. Using the USB-C saving settings; select the connected charger below."
    if external and any(b["status"] == "Discharging" for b in telemetry["batteries"]):
        warning += " Battery is discharging on external power. Reduce CPU/GPU load; brightness alone cannot guarantee charging."
    return {
        "source": source,
        "selection": selected,
        "label": labels[source],
        "brightness_percent": brightness,
        "power_profile": "performance" if source == "main" else "power-saver",
        "warning": warning.strip(),
        "key": [source, brightness],
    }


class Transition:
    """Let PowerDevil finish its own source transition; preserve later manual edits."""

    def __init__(self, settle_seconds=6):
        self.settle_seconds = settle_seconds
        self.pending = None
        self.since = 0
        self.applied = None

    def ready(self, key, now):
        if key != self.pending:
            self.pending, self.since = key, now
        return key != self.applied and now - self.since >= self.settle_seconds

    def complete(self):
        self.applied = self.pending
