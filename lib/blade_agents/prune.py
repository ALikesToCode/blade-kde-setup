"""Plan and apply the removal of finished worktrees and branches."""

import argparse
from dataclasses import dataclass, field
import datetime
import os
from pathlib import Path
import subprocess
import sys
import time

from . import worktrees as wt


@dataclass(frozen=True)
class Removal:
    repo: Path
    kind: str
    path: Path | None
    branch: str | None
    head: str
    verdict: wt.Verdict
    remote: bool


@dataclass(frozen=True)
class Kept:
    repo: Path
    kind: str
    name: str
    reason: str


@dataclass
class Context:
    owner: str | None
    cutoff: float
    recent_hours: float
    busy_t3: set
    process_dirs: set
    pull_requests: object = wt.github_pull_requests
    slug: object = wt.github_slug


@dataclass
class Plan:
    removals: list = field(default_factory=list)
    kept: list = field(default_factory=list)
    skipped_repos: list = field(default_factory=list)
    prunable: dict = field(default_factory=dict)


def worktree_blocker(repo, tree, default_branch, context):
    """Return why a linked worktree must stay before looking at its history, or None."""
    resolved = str(tree.path.resolve())
    if tree.locked:
        return "locked"
    if tree.branch and (tree.branch == default_branch or wt.LONG_LIVED.fullmatch(tree.branch)):
        return "checks out the default or a long-lived branch"
    if resolved in context.busy_t3:
        return "a T3 thread is running, queued, or recently active on it"
    if wt.used_by_process(resolved, context.process_dirs):
        return "a process is working in it"
    return None


def plan_worktree(repo, main, tree, default, default_branch, pull_requests, owned, context):
    blocker = worktree_blocker(repo, tree, default_branch, context)
    if blocker is None:
        verdict = wt.judge(repo, tree.head, pull_requests.get(tree.branch, []) if tree.branch else [],
                           default)
        if not verdict.finished:
            blocker = verdict.reason
        elif wt.changed_since(tree.path, wt.admin_directory(tree.path) or tree.path, context.cutoff):
            blocker = f"changed in the last {context.recent_hours:g} hours"
        elif not wt.is_clean(tree.path):
            blocker = "has uncommitted or untracked files"
        elif secrets := wt.unique_secrets(tree.path, main):
            blocker = f"holds ignored env or key files the main checkout lacks: {', '.join(secrets[:3])}"
    if blocker:
        return Kept(repo, "worktree", str(tree.path), blocker)
    remote = bool(owned and tree.branch and wt.remote_branch_finished(repo, tree.branch, verdict))
    return Removal(repo, "worktree", tree.path, tree.branch, tree.head, verdict, remote)


def local_branches(repo):
    output = wt.git(repo, "for-each-ref",
                    "--format=%(refname:short)%09%(objectname)%09%(committerdate:unix)", "refs/heads")
    for line in output.splitlines():
        name, head, committed = line.split("\t")
        yield name, head, int(committed or 0)


def plan_branch(repo, name, head, committed, logs, default, pull_requests, owned, context):
    if wt.LONG_LIVED.fullmatch(name):
        return Kept(repo, "branch", name, "long-lived branch name")
    try:
        touched = max(committed, (logs / name).stat().st_mtime)
    except OSError:
        touched = committed
    if touched >= context.cutoff:
        return Kept(repo, "branch", name, f"updated in the last {context.recent_hours:g} hours")
    verdict = wt.judge(repo, head, pull_requests.get(name, []), default)
    if not verdict.finished:
        return Kept(repo, "branch", name, verdict.reason)
    remote = bool(owned and wt.remote_branch_finished(repo, name, verdict))
    return Removal(repo, "branch", None, name, head, verdict, remote)


def plan_repo(repo, context, plan):
    trees = wt.list_worktrees(repo)
    branches = list(local_branches(repo))
    if len(trees) == 1 and len(branches) <= 1:
        return
    wt.git(repo, "fetch", "--quiet", "--prune", "origin", timeout=600)
    default = wt.default_ref(repo)
    if default is None:
        raise wt.PruneError("origin/HEAD is not set; run git remote set-head origin --auto")
    default_branch = default.removeprefix("refs/remotes/origin/")
    slug = context.slug(repo)
    pull_requests = context.pull_requests(slug) if slug else {}
    owned = bool(slug and context.owner and slug[0].lower() == context.owner.lower())
    checked_out = {tree.branch for tree in trees if tree.branch}
    prunable = [tree for tree in trees[1:] if tree.prunable]
    if prunable:
        plan.prunable[repo] = prunable
    for tree in trees[1:]:
        if not tree.prunable:
            item = plan_worktree(repo, trees[0].path, tree, default, default_branch, pull_requests,
                                 owned, context)
            (plan.removals if isinstance(item, Removal) else plan.kept).append(item)
    common = wt.git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    logs = Path(common) / "logs/refs/heads"
    for name, head, committed in branches:
        if name in checked_out or name == default_branch:
            continue
        item = plan_branch(repo, name, head, committed, logs, default, pull_requests, owned, context)
        (plan.removals if isinstance(item, Removal) else plan.kept).append(item)


def describe(item):
    if isinstance(item, Kept):
        return f"KEEP    {item.kind:8} {item.repo.name}  {item.name}: {item.reason}"
    target = item.path if item.kind == "worktree" else item.branch
    branch = f" [{item.branch}]" if item.kind == "worktree" and item.branch else ""
    remote = " + origin branch" if item.remote else ""
    return (f"REMOVE  {item.kind:8} {item.repo.name}  {target}{branch}  {item.head[:10]}  "
            f"{item.verdict.reason}{remote}")


def log_removal(log, item, remote_deleted):
    new = not log.exists()
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a") as stream:
        if new:
            stream.write("# time\trepo\tkind\tpath\tbranch\tpr\thead\torigin_branch_deleted\n"
                         "# restore a branch: git -C <repo> branch <branch> <head>, "
                         "or the PR's Restore branch button\n")
        number = f"#{item.verdict.pull_request.number}" if item.verdict.pull_request else "-"
        stream.write("\t".join([datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
                                str(item.repo), item.kind, str(item.path or "-"), item.branch or "-",
                                number, item.head, "yes" if remote_deleted else "no"]) + "\n")


def apply(item, log):
    """Remove one planned item; `git worktree remove` itself refuses a dirty tree."""
    if item.kind == "worktree":
        if not wt.is_clean(item.path):
            raise wt.PruneError(f"{item.path} is no longer clean")
        wt.git(item.repo, "worktree", "remove", str(item.path))
    if item.branch:
        tip = wt.git(item.repo, "rev-parse", "-q", "--verify", f"refs/heads/{item.branch}", check=False)
        if tip and tip != item.head:
            raise wt.PruneError(f"branch {item.branch} moved to {tip[:10]}; kept it")
        if tip:
            wt.git(item.repo, "branch", "-D", item.branch)
    remote_deleted = False
    if item.remote:
        remote_deleted = subprocess.run(
            ["git", "-C", str(item.repo), "push", "--quiet", "origin", "--delete", item.branch],
            capture_output=True, text=True, timeout=300, check=False).returncode == 0
    log_removal(log, item, remote_deleted)
    return remote_deleted


def prune_missing(repo, trees, apply_changes):
    """Drop Git's records of deleted worktrees, unless their volume just isn't mounted."""
    if any(not tree.path.parent.exists() for tree in trees):
        return (f"KEEP    records  {repo.name}  {len(trees)} missing worktrees: "
                "a parent directory is missing too")
    if apply_changes:
        wt.git(repo, "worktree", "prune")
    verb = "PRUNED " if apply_changes else "PRUNE  "
    return f"{verb} records  {repo.name}  " + ", ".join(str(tree.path) for tree in trees)


def discover(root):
    return sorted(path for path in root.iterdir() if (path / ".git").is_dir())


def github_login():
    result = subprocess.run(["gh", "api", "user", "--jq", ".login"], capture_output=True,
                            text=True, timeout=60, check=False)
    return result.stdout.strip() or None


def parser():
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    root = argparse.ArgumentParser(
        prog="blade-prune-worktrees",
        description="Remove worktrees and branches whose work is merged. Dry run unless --apply.")
    root.add_argument("repos", nargs="*", type=Path,
                      help="repositories (default: every one under --root)")
    root.add_argument("--apply", action="store_true", help="remove what the dry run lists")
    root.add_argument("--root", type=Path, default=Path.home() / "storage/github")
    root.add_argument("--recent-hours", type=float, default=6.0,
                      help="keep anything changed this recently (default 6)")
    root.add_argument("--owner", default=os.environ.get("BLADE_PRUNE_OWNER"),
                      help="delete origin branches only on this GitHub owner's repositories "
                           "(default: the signed-in gh user)")
    root.add_argument("--t3-database", type=Path,
                      default=Path.home() / ".t3/userdata/statev2.sqlite")
    root.add_argument("--log", type=Path, default=state / "blade-prune-worktrees/removed.tsv")
    return root


def run(argv=None):
    args = parser().parse_args(argv)
    cutoff = time.time() - args.recent_hours * 3600
    try:
        since = datetime.datetime.fromtimestamp(cutoff).astimezone()
        busy = wt.busy_t3_worktrees(args.t3_database, since)
    except wt.PruneError as error:
        print(f"blade-prune-worktrees: {error}; nothing removed", file=sys.stderr)
        return 1
    context = Context(args.owner or github_login(), cutoff, args.recent_hours, busy,
                      wt.process_directories())
    plan = Plan()
    for repo in [path.resolve() for path in args.repos] or discover(args.root):
        try:
            plan_repo(repo, context, plan)
        except (wt.PruneError, subprocess.TimeoutExpired, OSError, ValueError) as error:
            plan.skipped_repos.append((repo, str(error)))
    for item in sorted(plan.kept, key=lambda item: (item.repo.name, item.kind, item.name)):
        print(describe(item))
    for repo, error in plan.skipped_repos:
        print(f"SKIP    repo     {repo.name}: {error}")
    failures = 0
    for item in plan.removals:
        print(describe(item))
        if args.apply:
            try:
                apply(item, args.log)
            except (wt.PruneError, subprocess.TimeoutExpired, OSError) as error:
                failures += 1
                print(f"FAILED  {item.kind:8} {item.repo.name}  {error}", file=sys.stderr)
    for repo, trees in plan.prunable.items():
        print(prune_missing(repo, trees, args.apply))
    worktrees = sum(item.kind == "worktree" for item in plan.removals)
    remotes = sum(item.remote for item in plan.removals)
    verb = "Removed" if args.apply else "Would remove"
    print(f"\n{verb} {worktrees} worktrees and {len(plan.removals) - worktrees} other branches "
          f"({remotes} on origin); kept {len(plan.kept)}; skipped {len(plan.skipped_repos)} repositories"
          + (f"; {failures} failed" if failures else "") + ".")
    if args.apply and plan.removals:
        print(f"Log: {args.log}")
    return 1 if failures else 0
