# Hardened workspace launcher

The optional launcher preserves a real interactive terminal while placing the
entire development/browser process tree inside a fail-closed Firejail boundary
and an inner Landlock workspace-write policy. This is the configuration that
fixes `stdin is not a terminal`: standard input, output, and error stay attached
to the caller's TTY instead of being piped through another process.

Only configuration, wrappers, checksums, and an idempotent installer are stored
in this repository. Browser profiles, authentication, caches, session state,
downloads, test repositories, and third-party binary archives are excluded.

## Preconditions

The normal package manifest supplies Firejail, curl, jq, pipx, ripgrep, and the
other command-line dependencies. Before staging, the target username must be a
standalone line in `/etc/firejail/firejail.users`; this bounded system change is
left manual so the installer never edits an access-control list implicitly.

The following externally obtained, verified assets must already exist:

- CloakBrowser source tag `v0.4.11` at
  `~/.local/share/codex-safe/cloakbrowser-source-v0.4.11/`;
- patched Chromium `146.0.7680.177.5` at
  `~/.cloakbrowser/chromium-146.0.7680.177.5/`;
- `@playwright/cli` `0.1.17` and `@playwright/mcp` `0.0.78` below
  `~/.local/share/codex-safe/playwright-cli/`;
- standalone ShellCheck `0.11.0` at
  `~/.local/share/codex-safe/tools/shellcheck`.

The expected source commit, release archive, executable hashes, and attestation
receipt are recorded in
`extras/hardened-workspace/payload/home/.config/codex-safe/PROVENANCE.md`.
The installer rechecks the executable hashes and refuses mismatches.

## Install

Preview the repository-level integration:

```bash
./install.sh --dry-run --hardened
```

Then stage the wrappers and add the shell/browser policy:

```bash
./install.sh --hardened
```

The installer records a pre-install baseline beneath
`~/.config/codex-safe/backups/`. Re-running it is safe: matching files are left
alone, and the original executable is retained through a read-only link.

## Use and verify

Start it from a normal project directory—not `/`, the home directory, a mount
root, or a temporary-system root:

```bash
codex-safe
codex-safe exec "inspect this project"
```

The wrapper rejects unsafe launch roots, linked-file aliases, missing sandbox
controls, changed browser hashes, and unavailable local CDP endpoints. Run the
read-only doctor first, then the contained self-test when wanted:

```bash
~/.config/codex-safe/doctor.sh
~/.config/codex-safe/doctor.sh --run
~/.config/codex-safe/test-sandbox.sh
```

The payload README documents the exact filesystem boundary, browser attachment,
linked-worktree behavior, and explicit manifest-based uninstall operation.
