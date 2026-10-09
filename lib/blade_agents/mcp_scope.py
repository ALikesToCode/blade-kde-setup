"""Keep rarely used MCP servers off by default and opt single projects back in."""

import os
from pathlib import Path
import subprocess

from .codex_config import ConfigError, parse, set_key

# Codex starts a private copy of every enabled stdio server for each thread and
# keeps it until the thread closes; these domain servers hold 40-130 MB each.
HEAVY_SERVERS = ("artemis", "blender-lab", "higgsfield-use-blender")
PROJECT_CONFIG = ".codex/config.toml"


def codex_home():
    return Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))


def user_config_path():
    return codex_home() / "config.toml"


def _server_enabled(text, name, origin):
    return parse(text, origin).get("mcp_servers", {}).get(name, {}).get("enabled", True)


def disable_heavy(text):
    """Return the user config with every configured heavy server disabled."""
    servers = parse(text, "Codex user config").get("mcp_servers", {})
    for name in HEAVY_SERVERS:
        if name in servers and servers[name].get("enabled", True):
            text = set_key(text, f"mcp_servers.{name}", "enabled", "false")
            if _server_enabled(text, name, "updated Codex user config"):
                raise ConfigError(f"could not disable {name}")
    return text


def set_project(text, name, enabled):
    """Codex merges this one key over the user-level server definition."""
    text = set_key(text, f"mcp_servers.{name}", "enabled", "true" if enabled else "false")
    if _server_enabled(text, name, "updated project config") is not enabled:
        raise ConfigError(f"could not set {name} in the project config")
    return text


def _git(root, *arguments):
    return subprocess.run(["git", "-C", str(root), *arguments],
                          capture_output=True, text=True, check=False)


def project_root(directory):
    """Return the checkout root and whether it is a Git work tree."""
    result = _git(directory, "rev-parse", "--show-toplevel")
    if result.returncode == 0:
        return Path(result.stdout.strip()), True
    return directory.resolve(), False


def ignore_locally(root):
    """Keep an untracked project config out of commits without editing .gitignore."""
    if _git(root, "ls-files", "--error-unmatch", PROJECT_CONFIG).returncode == 0:
        return False
    exclude = Path(_git(root, "rev-parse", "--git-path", "info/exclude").stdout.strip())
    if not exclude.is_absolute():
        exclude = root / exclude
    entry = f"/{PROJECT_CONFIG}"
    existing = exclude.read_text().splitlines() if exclude.exists() else []
    if entry in existing:
        return False
    exclude.parent.mkdir(parents=True, exist_ok=True)
    with exclude.open("a") as stream:
        if existing and existing[-1].strip():
            stream.write("\n")
        stream.write(f"{entry}\n")
    return True


def is_trusted(user_config, root):
    """Codex ignores project config in folders the user has not trusted."""
    entry = user_config.get("projects", {}).get(str(root), {})
    return entry.get("trust_level") == "trusted"
