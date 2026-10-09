"""Command-line entry point for blade-agents."""

import argparse
from pathlib import Path
import sys

from . import files, hardware, mcp_scope, processes
from .codex_config import ConfigError, parse

KIB_PER_GIB = 1024 * 1024


def status(_args):
    totals = processes.summarise(processes.read_processes())
    print(f"{'MCP server':24}{'copies':>8}{'RAM GiB':>9}{'swap GiB':>10}")
    for name, (copies, rss, swap) in totals.items():
        print(f"{name:24}{copies:8}{rss / KIB_PER_GIB:9.2f}{swap / KIB_PER_GIB:10.2f}")
    available, swap_total, swap_free, stall = processes.memory_summary()
    summary = (f"\nAvailable memory {available / KIB_PER_GIB:.1f} GiB, swap "
               f"{(swap_total - swap_free) / KIB_PER_GIB:.1f}/{swap_total / KIB_PER_GIB:.1f} GiB used")
    if stall is not None:
        summary += f", every task stalled on memory {stall:.1f}% of the last 5 minutes"
    print(summary)
    return 0


def show_hardware(_args):
    print(hardware.report(hardware.detect()))
    return 0


def _write(path, current, updated, dry_run, label):
    if updated == current:
        print(f"{label} is already configured: {path}")
    elif dry_run:
        print(f"Would update {label}: {path}")
    else:
        files.replace(path, updated)
        print(f"Updated {label}: {path}")
    return 0


def configure(args):
    path = mcp_scope.user_config_path()
    current = files.read_text(path)
    updated = mcp_scope.share_code_review_graph(mcp_scope.disable_heavy(current))
    gpu_env = mcp_scope.blender_gpu_env(files.data_root() / "blade-kde/blender/scripts",
                                        mcp_scope.NVIDIA_EGL_VENDOR)
    updated = mcp_scope.render_blender_on_gpu(updated, gpu_env)
    return _write(path, current, updated, args.dry_run, "Codex user config")


def project(args):
    user = parse(files.read_text(mcp_scope.user_config_path()), "Codex user config")
    if args.server not in user.get("mcp_servers", {}):
        print(f"blade-agents: {args.server} is not defined in {mcp_scope.user_config_path()}",
              file=sys.stderr)
        return 1
    root, is_git = mcp_scope.project_root(Path(args.path))
    path = root / mcp_scope.PROJECT_CONFIG
    current = files.read_text(path)
    updated = mcp_scope.set_project(current, args.server, args.action == "enable")
    _write(path, current, updated, args.dry_run, "project config")
    if is_git and not args.dry_run and mcp_scope.ignore_locally(root):
        print(f"Excluded /{mcp_scope.PROJECT_CONFIG} in this checkout's .git/info/exclude")
    if not mcp_scope.is_trusted(user, root):
        print(f"Note: {root} is not marked trusted in {mcp_scope.user_config_path()}; "
              "Codex reads project config only after you trust the folder.", file=sys.stderr)
    print("New Codex threads in this project pick up the change; running threads keep their servers.")
    return 0


def parser():
    root = argparse.ArgumentParser(
        prog="blade-agents",
        description="Stop agent MCP servers from piling up one copy per thread.")
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("status", help="show copies and memory held by each MCP server")
    commands.add_parser("hardware", help="show the CPU, memory, and accelerators with live headroom")
    configure_command = commands.add_parser(
        "configure",
        help="disable the heavy MCP servers, share one code-review-graph server, "
             "and put the Blender servers on the GPU")
    configure_command.add_argument("-n", "--dry-run", action="store_true")
    mcp = commands.add_parser("mcp", help="enable or disable one server for one project")
    mcp.add_argument("action", choices=("enable", "disable"))
    mcp.add_argument("server")
    mcp.add_argument("path", nargs="?", default=".")
    mcp.add_argument("-n", "--dry-run", action="store_true")
    return root


def run(argv=None):
    args = parser().parse_args(argv)
    handler = {"status": status, "hardware": show_hardware, "configure": configure,
               "mcp": project}[args.command]
    try:
        sys.exit(handler(args))
    except (ConfigError, OSError) as error:
        print(f"blade-agents: {error}", file=sys.stderr)
        sys.exit(1)
