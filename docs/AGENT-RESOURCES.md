# Agent resources

Run the following inside the logged-in session:

```sh
./install.sh --dry-run --agents
./install.sh --agents
```

Many Codex and Claude agents work on this machine at once. Blade Agents keeps
what they start from piling up, without taking any tool away from the projects
that use it. Nothing it does stops a running agent: new threads pick up the
changes, and running threads keep their servers until they close.

## MCP servers

Codex starts a private copy of every enabled stdio MCP server for each thread
and keeps it until the thread closes. After a day of parallel work that was
about a hundred idle copies of each server, over 25 GB between RAM and swap.

| Server | Before | After |
| --- | --- | --- |
| `code-review-graph` | One copy per thread | One shared `code-review-graph.service` on `127.0.0.1:47555` |
| `artemis`, `blender-lab`, `higgsfield-use-blender` | One copy per thread | Off, except in projects that turn them on |

The shared code-review-graph server has no default repository. Agents pass the
absolute repository or worktree root as `repo_root` on every call, as the agent
instructions require. The server runs from an empty runtime directory, so a
call without it sees an empty graph instead of indexing the home-directory
checkout. Port 5555, the upstream default, is the Android emulator console.

Turn a heavy server on for one project, or off again:

```sh
blade-agents mcp enable artemis ~/storage/github/OMNI
blade-agents mcp disable artemis ~/storage/github/OMNI
```

This writes `enabled = true` to the project's `.codex/config.toml`, which Codex
merges over the definition in `~/.codex/config.toml`, and excludes the file in
that checkout's `.git/info/exclude` when it is not already tracked. Codex reads
project config only in folders you have trusted.

See what each server holds right now:

```sh
blade-agents status
```

`blade-agents configure` makes the global change by itself; `--agents` runs it
after the shared server answers. Codex Desktop rewrites `~/.codex/config.toml`
from its settings screen, so run it again if a server comes back. Each change
backs the file up under `~/.local/state/blade-kde-backups/`.

## Test runs

`blade-testlock COMMAND` runs a command once one of `BLADE_TEST_SLOTS` (3 by
default) machine-wide slots is free, and returns its exit status:

```sh
blade-testlock pnpm test
BLADE_TEST_SLOTS=2 blade-testlock cargo test
```

Agents call test runners directly, so the wrapper is opt-in: the global agent
instructions ask for targeted tests while iterating and `blade-testlock` for
full suites and production builds.
