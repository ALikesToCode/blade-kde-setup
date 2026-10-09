"""Measure the memory held by every copy of each agent MCP server."""

from pathlib import Path
import re

SERVERS = {
    "artemis": re.compile(r"artemis\S*\s.*-m mcp_server"),
    "blender-lab": re.compile(r"(?<![\w-])blender-mcp(\s|$)"),
    "higgsfield-use-blender": re.compile(r"fnf-blender-mcp"),
    "code-review-graph": re.compile(r"code-review-graph serve"),
    "node_repl": re.compile(r"/node_repl(\s|$)"),
}
# Shells and search tools often carry a server name in their arguments.
NOT_SERVERS = {"bash", "sh", "zsh", "fish", "rg", "grep", "pgrep", "pkill"}


def _kib(status, field):
    match = re.search(rf"^{field}:\s+(\d+) kB", status, re.M)
    return int(match.group(1)) if match else 0


def read_processes(proc=Path("/proc")):
    """Yield (argv, rss KiB, swap KiB) for every readable process."""
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "cmdline").read_bytes()
            status = (entry / "status").read_text()
        except OSError:
            continue
        argv = [part.decode(errors="replace") for part in raw.split(b"\0") if part]
        if argv:
            yield argv, _kib(status, "VmRSS"), _kib(status, "VmSwap")


def summarise(processes):
    """Return {server: [copies, rss KiB, swap KiB]}."""
    totals = {name: [0, 0, 0] for name in SERVERS}
    for argv, rss, swap in processes:
        if Path(argv[0]).name in NOT_SERVERS:
            continue
        command = " ".join(argv)
        for name, pattern in SERVERS.items():
            if pattern.search(command):
                totals[name][0] += 1
                totals[name][1] += rss
                totals[name][2] += swap
                break
    return totals


def memory_summary(proc=Path("/proc")):
    """Return available KiB, swap total and free KiB, and the 5-minute full stall %."""
    meminfo = {}
    for line in (proc / "meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        meminfo[key] = int(value.split()[0])
    stall = None
    try:
        match = re.search(r"^full .*avg300=([\d.]+)", (proc / "pressure/memory").read_text(), re.M)
        stall = float(match.group(1)) if match else None
    except OSError:
        pass
    return meminfo["MemAvailable"], meminfo["SwapTotal"], meminfo["SwapFree"], stall
