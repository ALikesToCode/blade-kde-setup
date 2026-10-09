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
| `code-review-graph` | One copy per thread | One shared `code-review-graph.service` on `127.0.0.1:14155` |
| `artemis`, `blender-lab`, `higgsfield-use-blender` | One copy per thread | Off, except in projects that turn them on |

The shared code-review-graph server has no default repository. Agents pass the
absolute repository or worktree root as `repo_root` on every call, as the agent
instructions require. The server runs from an empty runtime directory, so a
call without it fails with "repo_root does not look like a project" instead of
indexing the home-directory checkout. Port 5555, the upstream default, is the Android emulator console, and
ports from 32768 up can be taken by outbound connections.

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

## Hardware

The global agent instructions describe the CPU, memory, RTX GPU, integrated
GPU, and NPU, and when to reach for each. `blade-agents hardware` adds what
changes minute to minute: idle threads, available memory, free VRAM, and which
hardware encoders and GPU tools are installed.

```sh
blade-agents hardware
```

## Blender on the GPU

Both Blender MCP servers run Blender headless, and `higgsfield-use-blender`
adds `--factory-startup`, so the user's preferences never reach them. Cycles
then renders on the CPU, and EEVEE renders through Mesa on the integrated GPU.
`blade-agents configure` gives both servers:

- `BLENDER_SYSTEM_SCRIPTS` pointing at `~/.local/share/blade-kde/blender/scripts`,
  whose `startup/blade_gpu.py` switches every Cycles render to OptiX (then
  CUDA, HIP, oneAPI) with the GPU alone. It runs even under
  `--factory-startup`, and `BLADE_BLENDER_DEVICE=CPU` keeps a session on the CPU.
- The NVIDIA PRIME offload variables, including the NVIDIA EGL vendor file, so
  headless EEVEE and the viewport render on the RTX GPU. Measured here, a 4K
  256-sample EEVEE frame took 0.8 s on the RTX 5090 against 8.7 s on the
  integrated GPU. They are added only when the NVIDIA EGL vendor file exists.

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

## File indexing

Every agent worktree under `~/storage/github` is another full copy of a
checkout, and Baloo was holding over three million indexed files. The machine
snapshot excludes `~/storage/github/` from Baloo; Baloo's built-in filters
already skip `node_modules`, `.git`, and virtual environments elsewhere. Apply
it to a running session without a full restore:

```sh
balooctl6 config add excludeFolders "$HOME/storage/github"
```

## Memory headroom

The machine snapshot sizes zram at half of RAM (at most 32 GiB uncompressed)
instead of a quarter. zram is resized only at boot: restarting it live would
first have to move everything already in swap back into RAM.

`scripts/add-swapfile.sh` adds a 16 GiB `/swapfile` at priority 10, below
zram's 100, and records it in `/etc/fstab`. zram still fills first; the disk
only takes pages after that, instead of the OOM killer ending a process. It
takes effect immediately and asks for sudo:

```sh
scripts/add-swapfile.sh --dry-run
scripts/add-swapfile.sh
```

## Checkout storage

`~/storage` is an NTFS drive mounted through FUSE `ntfs-3g`, a user-space
driver that spends one CPU core on heavy small-file work: every `git status`,
`node_modules` lookup, and test run of every agent goes through it. The best
fix is to keep active checkouts and worktrees on the ext4 `/home` drive. When
they have to stay on NTFS, the in-kernel `ntfs3` driver is much faster:

```sh
scripts/switch-storage-ntfs3.sh --dry-run
scripts/switch-storage-ntfs3.sh
```

The script only rewrites the `/etc/fstab` entry, after `findmnt --verify`
accepts it, and keeps a dated backup next to it. It never remounts, so the
change arrives with the next boot. Unlike `ntfs-3g`, `ntfs3` will not mount a
volume Windows left dirty (Fast Startup, hibernation, or an unclean shutdown);
the entry keeps `nofail`, so the system still boots, but `~/storage` is then
missing until the volume is cleaned or the backup is restored.
