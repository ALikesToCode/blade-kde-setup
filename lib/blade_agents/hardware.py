"""Describe the CPU, memory, and accelerators agents can use, with live headroom."""

import os
from pathlib import Path
import re
import shutil
import subprocess

NVIDIA_QUERY = "index,name,memory.total,memory.used,utilization.gpu,driver_version"
ENCODERS = re.compile(r"\b((?:h264|hevc|av1)_(?:nvenc|qsv|vaapi))\b")
TOOLS = ("nvcc", "prime-run", "ollama", "ffmpeg", "clinfo", "vulkaninfo")


def count_cpus(ranges):
    """Count CPUs in a sysfs list such as '0-7,16,18-19'."""
    total = 0
    for part in filter(None, ranges.strip().split(",")):
        first, _, last = part.partition("-")
        total += int(last or first) - int(first) + 1
    return total


def parse_nvidia(csv):
    gpus = []
    for line in csv.strip().splitlines():
        index, name, total, used, utilisation, driver = (field.strip() for field in line.split(","))
        gpus.append({"index": int(index), "name": name, "total_mib": int(total),
                     "free_mib": int(total) - int(used), "busy": int(utilisation),
                     "driver": driver})
    return gpus


def parse_lspci(text):
    """Return '<vendor> <device>' for display controllers and accelerators."""
    devices = []
    for line in text.splitlines():
        fields = re.findall(r'"([^"]*)"', line)
        if len(fields) >= 3 and re.match(r"VGA|3D|Display|Processing accelerators", fields[0]):
            devices.append(f"{fields[1]} {fields[2]}")
    return devices


def _run(*command):
    if not shutil.which(command[0]):
        return ""
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=10,
                              check=False).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _read(path):
    try:
        return Path(path).read_text()
    except OSError:
        return ""


def detect():
    meminfo = {key: int(value.split()[0]) for key, value in
               (line.split(":", 1) for line in _read("/proc/meminfo").splitlines())}
    model = re.search(r"^model name\s*:\s*(.+)$", _read("/proc/cpuinfo"), re.M)
    nvcc = re.search(r"release ([\d.]+)", _run("nvcc", "--version"))
    return {
        "cpu": model.group(1) if model else "unknown CPU",
        "threads": os.cpu_count() or 1,
        "performance_cores": count_cpus(_read("/sys/devices/cpu_core/cpus")),
        "efficient_cores": count_cpus(_read("/sys/devices/cpu_atom/cpus")),
        "load": os.getloadavg()[0],
        "memory_kib": meminfo.get("MemTotal", 0),
        "available_kib": meminfo.get("MemAvailable", 0),
        "swap_free_kib": meminfo.get("SwapFree", 0),
        "devices": parse_lspci(_run("lspci", "-mm")),
        "nvidia": parse_nvidia(_run("nvidia-smi", f"--query-gpu={NVIDIA_QUERY}",
                                    "--format=csv,noheader,nounits")),
        "cuda": nvcc.group(1) if nvcc else None,
        "npu": sorted(str(path) for path in Path("/dev/accel").glob("accel*")),
        "encoders": sorted(set(ENCODERS.findall(_run("ffmpeg", "-hide_banner", "-encoders")))),
        "tools": [tool for tool in TOOLS if shutil.which(tool)],
    }


def report(facts):
    gib = 1024 * 1024
    cores = f"{facts['threads']} threads"
    if facts["performance_cores"] and facts["efficient_cores"]:
        cores += (f" ({facts['performance_cores']} performance cores, "
                  f"{facts['efficient_cores']} efficient cores)")
    idle = max(1, round(facts["threads"] - facts["load"]))
    lines = [
        f"CPU: {facts['cpu']}, {cores}; about {idle} threads idle now "
        f"(1-minute load {facts['load']:.1f})",
        f"Memory: {facts['memory_kib'] / gib:.0f} GiB, {facts['available_kib'] / gib:.1f} GiB "
        f"available, {facts['swap_free_kib'] / gib:.1f} GiB swap free",
    ]
    for gpu in facts["nvidia"]:
        cuda = f", CUDA {facts['cuda']}" if facts["cuda"] else ""
        lines.append(f"NVIDIA GPU {gpu['index']}: {gpu['name']}, {gpu['free_mib'] / 1024:.1f} of "
                     f"{gpu['total_mib'] / 1024:.0f} GiB VRAM free, {gpu['busy']}% busy, "
                     f"driver {gpu['driver']}{cuda}")
    nvidia_names = " ".join(gpu["name"] for gpu in facts["nvidia"])
    for device in facts["devices"]:
        if not device.startswith("NVIDIA") or not nvidia_names:
            lines.append(f"Device: {device}")
    if facts["npu"]:
        lines.append(f"NPU device nodes: {', '.join(facts['npu'])}")
    if facts["encoders"]:
        lines.append(f"Hardware video encoders (ffmpeg): {' '.join(facts['encoders'])}")
    if facts["tools"]:
        lines.append(f"GPU tooling on PATH: {' '.join(facts['tools'])}")
    return "\n".join(lines)
