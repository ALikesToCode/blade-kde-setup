"""Remove finished agent worktrees and branches, and nothing else.

A worktree or branch is finished when its pull request is merged and its HEAD
is that pull request's head commit or an ancestor of it, or when it never had a
pull request and its HEAD is already in the default branch. Even then it stays
while it has uncommitted or untracked files, while a T3 thread is running or
queued on it or was active recently, while a process works inside it, or while
anything in it changed recently.
"""

from contextlib import closing
from dataclasses import dataclass
import datetime
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess

# Runs in any other state are still working, queued, or waiting on the user.
FINISHED_RUNS = ("completed", "failed", "cancelled", "interrupted", "rolled_back")
SKIPPED_DIRS = {"node_modules", ".git"}
# Deploy and release branches can sit behind the default branch with no pull
# request of their own; they are never finished work.
LONG_LIVED = re.compile(r"(main|master|trunk|develop|development|dev|staging|stage|production|"
                        r"prod|preview|gh-pages|release|releases?/.*|deploy.*|hotfix.*)")
# Ignored files go with the worktree; these may hold credentials found nowhere else.
SECRET_FILES = re.compile(r"(?:^|/)(?:\.env[^/]*|\.dev\.vars[^/]*|[^/]*\.(?:pem|key|p12|jks|keystore)"
                          r"|[^/]*credentials[^/]*\.json|[^/]*service[-_]account[^/]*\.json)$")
GITHUB_REMOTE = re.compile(r"github\.com[:/](?P<owner>[^/]+)/(?P<name>[^/]+?)(?:\.git)?/?$")


class PruneError(Exception):
    pass


@dataclass(frozen=True)
class PullRequest:
    number: int
    state: str
    head: str


@dataclass(frozen=True)
class Worktree:
    path: Path
    head: str
    branch: str | None
    locked: bool
    prunable: bool


@dataclass(frozen=True)
class Verdict:
    finished: bool
    reason: str
    pull_request: PullRequest | None = None


def git(repo, *arguments, check=True, timeout=300):
    result = subprocess.run(["git", "-C", str(repo), *arguments], capture_output=True,
                            text=True, timeout=timeout, check=False)
    if check and result.returncode:
        raise PruneError(f"git {' '.join(arguments)} in {repo}: {result.stderr.strip()}")
    return result.stdout.strip()


def is_ancestor(repo, commit, descendant):
    return subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", commit,
                           descendant], capture_output=True, check=False).returncode == 0


def has_commit(repo, commit):
    return subprocess.run(["git", "-C", str(repo), "cat-file", "-e", f"{commit}^{{commit}}"],
                          capture_output=True, check=False).returncode == 0


def list_worktrees(repo):
    """Return the main checkout first, as Git does, then every linked worktree."""
    worktrees, entry = [], {}
    for line in git(repo, "worktree", "list", "--porcelain").splitlines() + [""]:
        if not line:
            if entry:
                worktrees.append(Worktree(Path(entry["worktree"]), entry.get("HEAD", ""),
                                          entry.get("branch", "").removeprefix("refs/heads/") or None,
                                          "locked" in entry, "prunable" in entry))
            entry = {}
            continue
        key, _, value = line.partition(" ")
        entry[key] = value
    return worktrees


def default_ref(repo):
    ref = git(repo, "symbolic-ref", "-q", "refs/remotes/origin/HEAD", check=False)
    return ref or None


def github_slug(repo):
    match = GITHUB_REMOTE.search(git(repo, "remote", "get-url", "origin", check=False))
    return (match["owner"], match["name"]) if match else None


def github_pull_requests(slug):
    """Map each head branch in the repository itself to its pull requests, newest first."""
    result = subprocess.run(
        ["gh", "pr", "list", "-R", "/".join(slug), "--state", "all", "--limit", "5000",
         "--json", "number,state,headRefName,headRefOid,isCrossRepository"],
        capture_output=True, text=True, timeout=300, check=False)
    if result.returncode:
        raise PruneError(f"gh pr list for {'/'.join(slug)}: {result.stderr.strip()}")
    by_branch = {}
    for item in sorted(json.loads(result.stdout), key=lambda item: -item["number"]):
        if not item["isCrossRepository"]:
            by_branch.setdefault(item["headRefName"], []).append(
                PullRequest(item["number"], item["state"], item["headRefOid"]))
    return by_branch


def judge(repo, head, pull_requests, default):
    """Decide whether HEAD is finished work, from its branch's pull requests."""
    open_requests = [request for request in pull_requests if request.state == "OPEN"]
    if open_requests:
        return Verdict(False, f"PR #{open_requests[0].number} is open")
    merged = [request for request in pull_requests if request.state == "MERGED"]
    for request in merged:
        if not has_commit(repo, request.head):
            git(repo, "fetch", "--quiet", "origin", f"pull/{request.number}/head", check=False)
        if head == request.head or is_ancestor(repo, head, request.head):
            return Verdict(True, f"merged in PR #{request.number}", request)
    if merged:
        return Verdict(False, f"has commits that merged PR #{merged[0].number} lacks")
    if pull_requests:
        return Verdict(False, f"PR #{pull_requests[0].number} was closed without merging")
    if default and is_ancestor(repo, head, default):
        return Verdict(True, "no PR; already in the default branch")
    return Verdict(False, "no PR and not in the default branch")


def remote_branch_finished(repo, branch, verdict):
    """True when origin's copy of BRANCH holds nothing beyond the merged pull request.

    A branch that never had a pull request may be someone's starting point, so
    only the local copy of it goes.
    """
    if verdict.pull_request is None:
        return False
    tip = git(repo, "rev-parse", "-q", "--verify", f"refs/remotes/origin/{branch}^{{commit}}",
              check=False)
    if not tip:
        return False
    return tip == verdict.pull_request.head or is_ancestor(repo, tip, verdict.pull_request.head)


def process_directories():
    directories = set()
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            try:
                directories.add(os.readlink(entry / "cwd").removesuffix(" (deleted)"))
            except OSError:
                pass
    return directories


def used_by_process(path, directories):
    prefix = f"{path}/"
    return any(directory == str(path) or directory.startswith(prefix) for directory in directories)


def busy_t3_worktrees(database, since):
    """Worktrees of T3 threads that are running, queued, or waiting, or were active since SINCE."""
    if not database.exists():
        return set()
    stamp = since.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    query = f"""
        SELECT DISTINCT json_extract(thread.payload_json, '$.worktreePath')
        FROM orchestration_v2_projection_threads AS thread
        WHERE thread.deleted_at IS NULL AND (thread.updated_at >= ? OR EXISTS (
            SELECT 1 FROM orchestration_v2_projection_runs AS run
            WHERE run.thread_id = thread.thread_id
              AND run.status NOT IN ({", ".join("?" * len(FINISHED_RUNS))})))
    """
    try:
        with closing(sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=30)) as db:
            rows = db.execute(query, (stamp, *FINISHED_RUNS)).fetchall()
    except sqlite3.Error as error:
        raise PruneError(f"cannot read T3 threads from {database}: {error}") from error
    return {str(Path(path).resolve()) for (path,) in rows if path}


def changed_since(path, admin, cutoff):
    """True when the worktree or its Git state changed after CUTOFF (a timestamp)."""
    for name in ("index", "HEAD", "logs/HEAD"):
        try:
            if (admin / name).stat().st_mtime >= cutoff:
                return True
        except OSError:
            pass
    pending = [path]
    while pending:
        try:
            with os.scandir(pending.pop()) as entries:
                for entry in entries:
                    if entry.stat(follow_symlinks=False).st_mtime >= cutoff:
                        return True
                    if entry.is_dir(follow_symlinks=False) and entry.name not in SKIPPED_DIRS:
                        pending.append(entry.path)
        except OSError:
            continue
    return False


def is_clean(path):
    """No modified tracked files and no untracked files that aren't ignored."""
    result = subprocess.run(["git", "-C", str(path), "--no-optional-locks", "status",
                             "--porcelain", "--ignore-submodules=none"],
                            capture_output=True, text=True, timeout=600, check=False)
    return result.returncode == 0 and not result.stdout.strip()


def unique_secrets(path, main):
    """Ignored env and key files in PATH that the main checkout lacks an identical copy of."""
    result = subprocess.run(["git", "-C", str(path), "ls-files", "--others", "--ignored",
                             "--exclude-standard", "--directory", "-z"],
                            capture_output=True, text=True, timeout=600, check=False)
    if result.returncode:
        raise PruneError(f"cannot list ignored files in {path}")
    unique = []
    for name in filter(None, result.stdout.split("\0")):
        if name.endswith("/") or not SECRET_FILES.search(name):
            continue
        try:
            if (path / name).read_bytes() == (main / name).read_bytes():
                continue
        except OSError:
            pass
        unique.append(name)
    return unique


def admin_directory(path):
    """The worktree's private Git directory, read from its .git file."""
    try:
        line = (path / ".git").read_text().strip()
    except OSError:
        return None
    if not line.startswith("gitdir: "):
        return None
    admin = Path(line.removeprefix("gitdir: "))
    return admin if admin.is_absolute() else (path / admin).resolve()
