#!/usr/bin/env python3
"""Exercise blade-prune-worktrees against throwaway repositories."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from blade_agents import prune
from blade_agents import worktrees as wt

ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
       "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid",
       "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}


def run(cwd, *arguments):
    return subprocess.run(arguments, cwd=cwd, env=ENV, capture_output=True, text=True,
                          check=True).stdout.strip()


class PruneTests(unittest.TestCase):
    def setUp(self):
        os.environ.update({key: value for key, value in ENV.items() if key.startswith("GIT_")})
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.origin, self.repo, self.trees = root / "origin.git", root / "repo", root / "trees"
        run(root, "git", "init", "-q", "--bare", "-b", "main", str(self.origin))
        run(root, "git", "clone", "-q", str(self.origin), str(self.repo))
        (self.repo / ".gitignore").write_text("node_modules/\n.env*\n")
        (self.repo / ".env.local").write_text("SHARED=1\n")
        self.commit(self.repo, "base")
        run(self.repo, "git", "push", "-q", "origin", "main")
        run(self.repo, "git", "remote", "set-head", "origin", "--auto")
        self.pulls = {}

    def tearDown(self):
        self.temporary.cleanup()

    def commit(self, where, name):
        (where / name).write_text(name)
        run(where, "git", "add", "-A")
        run(where, "git", "commit", "-q", "-m", name)
        return run(where, "git", "rev-parse", "HEAD")

    def worktree(self, branch, commit=True, push=True, state=None):
        path = self.trees / branch.replace("/", "-")
        run(self.repo, "git", "worktree", "add", "-q", "-b", branch, str(path), "origin/main")
        head = (self.commit(path, branch.replace("/", "-")) if commit
                else run(path, "git", "rev-parse", "HEAD"))
        if push:
            run(path, "git", "push", "-q", "origin", branch)
        if state:
            self.pulls.setdefault(branch, []).append(wt.PullRequest(len(self.pulls) + 1, state, head))
        return path

    def plan(self, busy=(), recent_hours=None):
        cutoff = time.time() + 60 if recent_hours is None else time.time() - recent_hours * 3600
        context = prune.Context("me", cutoff, recent_hours or 0, {str(Path(p).resolve()) for p in busy},
                                set(), pull_requests=lambda slug: self.pulls,
                                slug=lambda repo: ("me", "repo"))
        plan = prune.Plan()
        prune.plan_repo(self.repo, context, plan)
        return plan

    @staticmethod
    def names(items):
        return {Path(item.path).name if getattr(item, "path", None) else
                getattr(item, "branch", None) or item.name for item in items}

    def test_only_finished_clean_idle_work_is_removed(self):
        merged = self.worktree("feat/merged", state="MERGED")
        (merged / "node_modules").mkdir()
        (merged / "node_modules/x.js").write_text("ignored")
        (merged / ".env.local").write_text("SHARED=1\n")
        (self.worktree("feat/secret", state="MERGED") / ".env.local").write_text("TOKEN=only-here\n")
        (self.worktree("feat/dirty", state="MERGED") / "notes.txt").write_text("untracked")
        ahead = self.worktree("feat/ahead", state="MERGED")
        self.commit(ahead, "later")
        self.worktree("feat/open", state="OPEN")
        self.worktree("feat/closed", state="CLOSED")
        self.worktree("chore/idle", commit=False)
        busy = self.worktree("feat/busy", state="MERGED")
        self.worktree("feat/unpushed", push=False)
        run(self.repo, "git", "branch", "loose/merged", "origin/main")
        run(self.repo, "git", "branch", "staging", "origin/main")
        run(self.repo, "git", "branch", "loose/work", "feat/unpushed")
        run(self.repo, "git", "commit", "-q", "--allow-empty", "-m", "main moves on")

        plan = self.plan(busy=[busy])
        removed = {item.path.name if item.path else item.branch for item in plan.removals}
        self.assertEqual(removed, {"feat-merged", "chore-idle", "loose/merged"})
        reasons = {Path(item.name).name: item.reason for item in plan.kept}
        self.assertIn("uncommitted or untracked", reasons["feat-dirty"])
        self.assertIn(".env.local", reasons["feat-secret"])
        self.assertIn("lacks", reasons["feat-ahead"])
        self.assertIn("open", reasons["feat-open"])
        self.assertIn("closed without merging", reasons["feat-closed"])
        self.assertIn("T3 thread", reasons["feat-busy"])
        self.assertIn("not in the default branch", reasons["feat-unpushed"])
        self.assertIn("not in the default branch", reasons["work"])
        self.assertIn("long-lived", reasons["staging"])
        idle = next(item for item in plan.removals if item.branch == "chore/idle")
        self.assertFalse(idle.remote)

        merged_item = next(item for item in plan.removals if item.branch == "feat/merged")
        self.assertTrue(merged_item.remote)
        log = Path(self.temporary.name) / "state/removed.tsv"
        for item in plan.removals:
            prune.apply(item, log)
        self.assertFalse(merged.exists())
        branches = run(self.repo, "git", "branch", "--format=%(refname:short)").split()
        self.assertNotIn("feat/merged", branches)
        self.assertNotIn("loose/merged", branches)
        self.assertIn("feat/ahead", branches)
        self.assertNotIn("feat/merged", run(self.origin, "git", "branch").split())
        lines = [line for line in log.read_text().splitlines() if not line.startswith("#")]
        self.assertEqual(len(lines), 3)
        number = merged_item.verdict.pull_request.number
        self.assertTrue(any(line.endswith(f"\tfeat/merged\t#{number}\t{merged_item.head}\tyes")
                            for line in lines), lines)

    def test_recent_changes_keep_finished_work(self):
        self.worktree("feat/merged", state="MERGED")
        plan = self.plan(recent_hours=6)
        self.assertEqual(plan.removals, [])
        self.assertIn("changed in the last 6 hours", plan.kept[0].reason)

    def test_apply_refuses_a_tree_that_became_dirty(self):
        merged = self.worktree("feat/merged", state="MERGED")
        item = self.plan().removals[0]
        (merged / "late.txt").write_text("new")
        with self.assertRaises(wt.PruneError):
            prune.apply(item, Path(self.temporary.name) / "removed.tsv")
        self.assertTrue(merged.exists())

    def test_missing_volume_keeps_worktree_records(self):
        gone = wt.Worktree(Path(self.temporary.name) / "unmounted/tree", "", None, False, True)
        self.assertIn("parent directory is missing", prune.prune_missing(self.repo, [gone], True))


if __name__ == "__main__":
    unittest.main()
