#!/usr/bin/env python3
"""Mirror host X11 text clipboard data into the private Xephyr display."""

from __future__ import annotations

import argparse
import hashlib
import os
import select
import signal
import subprocess
import time

MAX_CLIPBOARD_BYTES = 4 * 1024 * 1024
POLL_SECONDS = 0.25
READ_TIMEOUT_SECONDS = 2.0


def display_environment(display: str, authority: str) -> dict[str, str]:
    environment = os.environ.copy()
    environment["DISPLAY"] = display
    environment["XAUTHORITY"] = authority
    environment["DBUS_SESSION_BUS_ADDRESS"] = "disabled:"
    environment["DBUS_SYSTEM_BUS_ADDRESS"] = "disabled:"
    return environment


def read_clipboard(xclip: str, environment: dict[str, str]) -> bytes | None:
    process = subprocess.Popen(
        [
            xclip,
            "-selection",
            "clipboard",
            "-out",
            "-target",
            "UTF8_STRING",
        ],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    assert process.stdout is not None
    deadline = time.monotonic() + READ_TIMEOUT_SECONDS
    chunks: list[bytes] = []
    size = 0
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                process.kill()
                return None
            readable, _, _ = select.select([process.stdout], [], [], remaining)
            if not readable:
                process.kill()
                return None
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                break
            size += len(chunk)
            if size > MAX_CLIPBOARD_BYTES:
                process.kill()
                return None
            chunks.append(chunk)
        if process.wait(timeout=0.5) != 0:
            return None
        return b"".join(chunks)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def stop_owner(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def start_clipboard_owner(
    xclip: str,
    environment: dict[str, str],
    content: bytes,
) -> subprocess.Popen[bytes] | None:
    process = subprocess.Popen(
        [
            xclip,
            "-selection",
            "clipboard",
            "-in",
            "-silent",
            "-loops",
            "0",
        ],
        env=environment,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    assert process.stdin is not None
    try:
        process.stdin.write(content)
        process.stdin.close()
    except BrokenPipeError:
        process.wait()
        return None
    time.sleep(0.05)
    if process.poll() is not None:
        return None
    return process


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host-display", required=True)
    parser.add_argument("--host-authority", required=True)
    parser.add_argument("--nested-display", required=True)
    parser.add_argument("--nested-authority", required=True)
    parser.add_argument("--xclip", required=True)
    parser.add_argument("--ready-file", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    host_environment = display_environment(
        args.host_display,
        args.host_authority,
    )
    nested_environment = display_environment(
        args.nested_display,
        args.nested_authority,
    )
    running = True

    def stop(_signum: int, _frame: object) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    last_digest: bytes | None = None
    owner: subprocess.Popen[bytes] | None = None
    with open(args.ready_file, "x", encoding="ascii") as ready:
        ready.write("ready\n")

    try:
        while running:
            content = read_clipboard(args.xclip, host_environment)
            if content is not None:
                digest = hashlib.sha256(content).digest()
                if digest != last_digest:
                    new_owner = start_clipboard_owner(
                        args.xclip,
                        nested_environment,
                        content,
                    )
                    if new_owner is not None:
                        stop_owner(owner)
                        owner = new_owner
                        last_digest = digest
                content = b""
            time.sleep(POLL_SECONDS)
    finally:
        stop_owner(owner)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
