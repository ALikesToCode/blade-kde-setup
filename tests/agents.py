#!/usr/bin/env python3
"""Exercise Codex config edits, project opt-in, and MCP process accounting."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from blade_agents import files, mcp_scope, processes
from blade_agents.codex_config import ConfigError, drop_key, set_key

USER_CONFIG = '''model = "m"

[mcp_servers.artemis]
command = "python"
args = [
    "-m",
    "mcp_server",
]
startup_timeout_sec = 120.0

[mcp_servers.artemis.env]
PYTHONUNBUFFERED = "1"

[mcp_servers."blender-lab"]
command = "uv"
enabled = true

[mcp_servers.context7]
url = "https://example.invalid/mcp"
'''


class EditTests(unittest.TestCase):
    def test_set_key_inserts_before_subtables_and_keeps_other_lines(self):
        text = set_key(USER_CONFIG, "mcp_servers.artemis", "enabled", "false")
        parsed = tomllib.loads(text)
        self.assertFalse(parsed["mcp_servers"]["artemis"]["enabled"])
        self.assertEqual(parsed["mcp_servers"]["artemis"]["env"], {"PYTHONUNBUFFERED": "1"})
        self.assertIn('startup_timeout_sec = 120.0\nenabled = false\n\n[mcp_servers.artemis.env]', text)

    def test_set_key_replaces_an_existing_value_in_a_quoted_table(self):
        text = set_key(USER_CONFIG, "mcp_servers.blender-lab", "enabled", "false")
        self.assertFalse(tomllib.loads(text)["mcp_servers"]["blender-lab"]["enabled"])
        self.assertEqual(text.count("enabled ="), 1)

    def test_set_key_appends_a_missing_table(self):
        text = set_key("", "mcp_servers.artemis", "enabled", "true")
        self.assertEqual(text, "[mcp_servers.artemis]\nenabled = true\n")

    def test_drop_key_removes_a_multiline_array(self):
        text = drop_key(USER_CONFIG, "mcp_servers.artemis", "args")
        artemis = tomllib.loads(text)["mcp_servers"]["artemis"]
        self.assertNotIn("args", artemis)
        self.assertEqual(artemis["command"], "python")


class ScopeTests(unittest.TestCase):
    def test_disable_heavy_only_touches_heavy_servers_and_is_idempotent(self):
        text = mcp_scope.disable_heavy(USER_CONFIG)
        servers = tomllib.loads(text)["mcp_servers"]
        self.assertFalse(servers["artemis"]["enabled"])
        self.assertFalse(servers["blender-lab"]["enabled"])
        self.assertNotIn("enabled", servers["context7"])
        self.assertEqual(mcp_scope.disable_heavy(text), text)

    def test_disable_heavy_rejects_invalid_toml(self):
        with self.assertRaises(ConfigError):
            mcp_scope.disable_heavy("[broken")

    def test_project_override_is_one_key(self):
        text = mcp_scope.set_project("", "artemis", True)
        self.assertEqual(tomllib.loads(text), {"mcp_servers": {"artemis": {"enabled": True}}})
        self.assertFalse(tomllib.loads(mcp_scope.set_project(text, "artemis", False))
                         ["mcp_servers"]["artemis"]["enabled"])

    def test_trust_requires_the_exact_project_entry(self):
        config = {"projects": {"/work/app": {"trust_level": "trusted"}}}
        self.assertTrue(mcp_scope.is_trusted(config, Path("/work/app")))
        self.assertFalse(mcp_scope.is_trusted(config, Path("/work/other")))

    def test_ignore_locally_excludes_an_untracked_project_config_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            self.assertEqual(mcp_scope.project_root(root / "."), (root.resolve(), True))
            self.assertTrue(mcp_scope.ignore_locally(root))
            self.assertFalse(mcp_scope.ignore_locally(root))
            exclude = (root / ".git/info/exclude").read_text().splitlines()
            self.assertEqual(exclude.count("/.codex/config.toml"), 1)


class FileTests(unittest.TestCase):
    def test_replace_backs_up_and_keeps_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "config.toml"
            target.write_text("old\n")
            target.chmod(0o640)
            os.environ["BLADE_BACKUP_ROOT"] = str(root / "backup")
            self.addCleanup(os.environ.pop, "BLADE_BACKUP_ROOT")
            files.replace(target, "new\n")
            self.assertEqual(target.read_text(), "new\n")
            self.assertEqual(target.stat().st_mode & 0o777, 0o640)
            backup = root / "backup" / str(target.resolve()).lstrip("/")
            self.assertEqual(backup.read_text(), "old\n")

    def test_replace_refuses_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "real").write_text("x")
            (root / "link").symlink_to(root / "real")
            with self.assertRaises(OSError):
                files.replace(root / "link", "y")


class ProcessTests(unittest.TestCase):
    def test_summarise_groups_copies_and_skips_shells(self):
        sample = [
            (["/opt/artemis/.venv/bin/python", "-m", "mcp_server"], 100, 10),
            (["/opt/artemis/.venv/bin/python", "-m", "mcp_server"], 100, 10),
            (["/usr/bin/uv", "--directory", "/x/blender_mcp/mcp", "run", "blender-mcp"], 5, 0),
            (["/x/.venv/bin/python", "/x/.venv/bin/blender-mcp"], 30, 1),
            (["/usr/bin/node", "/h/node_modules/fnf-blender-mcp/dist/index.js"], 20, 2),
            (["/usr/bin/bash", "-c", "pgrep -f 'artemis/.venv/bin/python -m mcp_server'"], 3, 0),
            (["code-review-graph", "serve", "--http"], 70, 0),
        ]
        totals = processes.summarise(sample)
        self.assertEqual(totals["artemis"], [2, 200, 20])
        self.assertEqual(totals["blender-lab"], [2, 35, 1])
        self.assertEqual(totals["higgsfield-use-blender"], [1, 20, 2])
        self.assertEqual(totals["code-review-graph"], [1, 70, 0])

    def test_memory_summary_reads_meminfo_and_pressure(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            (proc / "meminfo").write_text(
                "MemTotal: 100 kB\nMemAvailable: 40 kB\nSwapTotal: 16 kB\nSwapFree: 4 kB\n")
            (proc / "pressure").mkdir()
            (proc / "pressure/memory").write_text(
                "some avg10=0.00 avg60=0.60 avg300=7.34 total=1\n"
                "full avg10=0.00 avg60=0.57 avg300=7.07 total=1\n")
            self.assertEqual(processes.memory_summary(proc), (40, 16, 4, 7.07))


if __name__ == "__main__":
    unittest.main(verbosity=1)
