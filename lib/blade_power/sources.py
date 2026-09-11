"""Read Linux power-supply telemetry without guessing charger wattage."""

from pathlib import Path


def read_value(directory, name):
    try:
        return (directory / name).read_text().strip()
    except (OSError, UnicodeError):
        return ""


def number(directory, name):
    try:
        return float(read_value(directory, name))
    except ValueError:
        return None


def battery_info(directory):
    status = read_value(directory, "status") or "Unknown"
    watts = number(directory, "power_now")
    if watts is not None:
        watts /= 1_000_000
    else:
        voltage = number(directory, "voltage_now")
        current = number(directory, "current_now")
        if voltage is not None and current is not None:
            watts = abs(voltage * current) / 1_000_000_000_000
    if watts is not None:
        if status == "Discharging":
            watts = -abs(watts)
        elif status == "Charging":
            watts = abs(watts)
        else:
            watts = None
    return {
        "name": directory.name,
        "status": status,
        "capacity": number(directory, "capacity"),
        "net_watts": round(watts, 1) if watts is not None else None,
    }


def snapshot(root=Path("/sys/class/power_supply")):
    supplies, batteries = [], []
    for directory in sorted(root.glob("*")):
        kind = read_value(directory, "type")
        if read_value(directory, "scope") == "Device":
            continue
        if kind == "Battery":
            if read_value(directory, "present") != "0":
                batteries.append(battery_info(directory))
        elif kind and read_value(directory, "online") == "1":
            supplies.append({"name": directory.name, "type": kind})

    # ADP1/Mains can represent both barrel AC and USB-C on MSI firmware.
    # An absent USB device is not evidence that the large adapter is connected.
    if any(supply["type"].startswith("USB") for supply in supplies):
        detected = "usb"
    elif supplies:
        detected = "external"
    elif batteries and any(b["status"] == "Discharging" for b in batteries):
        detected = "battery"
    else:
        detected = "unavailable"
    return {"detected": detected, "supplies": supplies, "batteries": batteries}
