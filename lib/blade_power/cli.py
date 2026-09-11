"""Session service and command-line entry points for Blade charger controls."""

import argparse
import configparser
import fcntl
import json
import os
from pathlib import Path
import sys
import time

from blade_power.desktop import apply_policy, read_json, write_json
from blade_power.policy import Transition, decide, load_settings
from blade_power.sources import snapshot


def paths():
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise RuntimeError("XDG_RUNTIME_DIR is missing; run inside your logged-in desktop session")
    return config / "blade-power.conf", Path(runtime) / "blade-power"


def current(config, runtime):
    telemetry = snapshot()
    selection = read_json(runtime / "selection.json").get("mode", "auto")
    policy = decide(telemetry, selection, load_settings(config))
    state = read_json(runtime / "status.json")
    return {
        **telemetry,
        **policy,
        "service_active": time.time() - state.get("updated_at", 0) < 20,
        "last_error": state.get("error", ""),
        "last_applied": state.get("last_applied", {}),
    }


def watch(config, runtime):
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (runtime / "service.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("Blade power service is already running") from error
        loop(config, runtime)


def loop(config, runtime):
    transition = Transition()
    last_applied, previous_error, error = {}, "", ""
    retry_at = 0
    while True:
        try:
            status = current(config, runtime)
            if status["detected"] in ("battery", "unavailable"):
                selection = read_json(runtime / "selection.json")
                if selection.get("mode", "auto") != "auto":
                    write_json(runtime / "selection.json", {"mode": "auto"})
            selection = read_json(runtime / "selection.json")
            key = [*status["key"], selection.get("changed_at", 0)]
            now = time.monotonic()
            if key != transition.pending:
                retry_at = 0
            if transition.ready(key, now) and now >= retry_at:
                last_applied = {**apply_policy(status), "source": status["source"],
                                "brightness_percent": status["brightness_percent"],
                                "power_profile": status["power_profile"]}
                transition.complete()
                error = ""
                print(json.dumps(last_applied), flush=True)
        except (RuntimeError, ValueError, OSError, configparser.Error) as failure:
            error = str(failure)
            retry_at = time.monotonic() + 30
        if error and error != previous_error:
            print(error, file=sys.stderr, flush=True)
        previous_error = error
        write_json(runtime / "status.json", {"updated_at": time.time(), "error": error,
                                             "last_applied": last_applied})
        time.sleep(2)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Blade KDE charger-aware brightness and power controls")
    subparsers = parser.add_subparsers(dest="command", required=True)
    status_parser = subparsers.add_parser("status", help="Show observed power source, battery flow, and policy")
    status_parser.add_argument("--json", action="store_true")
    subparsers.add_parser("watch", help="Run the desktop-session service")
    mode_parser = subparsers.add_parser("mode", help="Select the connected charger; resets on disconnect or logout")
    mode_parser.add_argument("mode", choices=("auto", "main", "usb"))
    subparsers.add_parser("apply", help="Reapply the current policy once")
    args = parser.parse_args(argv)
    config, runtime = paths()
    if args.command == "watch":
        watch(config, runtime)
        return
    status = current(config, runtime)
    if args.command == "mode":
        if args.mode != "auto" and status["detected"] not in ("usb", "external"):
            raise RuntimeError("No external power detected; charger selection was not changed")
        write_json(runtime / "selection.json", {"mode": args.mode, "changed_at": time.time()})
        status = current(config, runtime)
    elif args.command == "apply":
        status["result"] = apply_policy(status)
    if args.command != "status" or args.json:
        print(json.dumps(status, ensure_ascii=False))
    else:
        print(status["label"])
        print(f"Brightness target: {status['brightness_percent']}%; profile: {status['power_profile']}")
        print(f"Service: {'running' if status['service_active'] else 'not running'}")
        for battery in status["batteries"]:
            print(f"{battery['name']}: {battery['capacity']}%, {battery['status']}; net battery power {battery['net_watts']} W")
        if status["warning"] or status["last_error"]:
            print(status["warning"] or status["last_error"])


def run():
    try:
        main()
    except (RuntimeError, ValueError, OSError, configparser.Error) as error:
        print(f"blade-power: {error}", file=sys.stderr)
        raise SystemExit(1) from error
