#!/usr/bin/env python3
"""Exercise fstab entry replacement, addition, and duplicate refusal."""

import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "fstab_entry", Path(__file__).resolve().parents[1] / "scripts/fstab-entry.py")
fstab_entry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fstab_entry)

FSTAB = """# /dev/nvme0n1p3 LABEL=ROOT
UUID=1   /                ext4    rw,relatime   0 1
# UUID=old /data ntfs-3g defaults 0 0
UUID=758 /data            ntfs-3g uid=1000      0 0
"""


class ReplaceEntryTests(unittest.TestCase):
    def test_replaces_only_the_live_entry_for_the_mount_point(self):
        text = fstab_entry.replace_entry(FSTAB, "/data", ["UUID=new", "/data", "ext4", "noatime", "0", "2"])
        lines = text.splitlines()
        self.assertEqual(lines[3], "UUID=new /data ext4 noatime 0 2")
        self.assertEqual(lines[:3], FSTAB.splitlines()[:3])

    def test_adds_a_missing_entry_after_a_blank_line(self):
        text = fstab_entry.replace_entry(FSTAB, "/win", ["UUID=w", "/win", "ntfs3", "noauto", "0", "0"])
        self.assertTrue(text.endswith("uid=1000      0 0\n\nUUID=w /win ntfs3 noauto 0 0\n"))

    def test_refuses_duplicate_entries(self):
        with self.assertRaises(ValueError):
            fstab_entry.replace_entry(FSTAB + "UUID=9 /data ext4 rw 0 2\n", "/data",
                                      ["UUID=x", "/data", "ext4", "rw", "0", "2"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
