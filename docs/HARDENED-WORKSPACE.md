# Hardened workspace launcher

The optional launcher preserves a real interactive terminal while placing the
entire development/browser process tree inside a fail-closed Firejail boundary
and an inner Landlock workspace-write policy. This is the configuration that
fixes `stdin is not a terminal`: standard input, output, and error stay attached
to the caller's TTY instead of being piped through another process.

Only configuration, wrappers, checksums, and an idempotent installer are stored
in this repository. The live browser profile, authentication, caches, session
state, downloads, test repositories, and third-party binary archives are
excluded.

## Preconditions

The normal package manifest supplies Firejail, curl, jq, pipx, ripgrep, Xephyr,
`xauth`, `xclip`, and the other command-line dependencies. `xclip` is used only
for the one-way host-to-Xephyr text clipboard bridge. Install `gnome-keyring`
as the isolated MCP Secret Service broker; it does not replace KDE Wallet as
the desktop backend.
The installer masks the package's user socket/service for this account and
starts the daemon only on codex-safe's private bus.
Before staging, the target username must be a
standalone line in `/etc/firejail/firejail.users`; this bounded system change is
left manual so the installer never edits an access-control list implicitly.

The following externally obtained, verified assets must already exist:

- CloakBrowser source tag `v0.4.11` at
  `~/.local/share/codex-safe/cloakbrowser-source-v0.4.11/`;
- the reviewed `cloakserve-codex-safe.patch` and bounded prior-installation
  upgrade patch, applied only after a known source hash matches, so Chromium
  commits the private browser profile through CDP before shutdown and headed
  mode does not forward Chromium's presence-sensitive `--headless=false`
  switch;
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
sudo pacman -S --needed gnome-keyring
./install.sh --hardened
codex-safe-migrate-mcp
```

The installer records a pre-install baseline beneath
`~/.config/codex-safe/backups/`. Re-running it is safe: matching files are left
alone, and the original executable is retained through a read-only link.

## Use and verify

Start it from a normal project directory—not `/`, the home directory, a mount
root, or a temporary-system root:

```bash
codex
```

The hardened launcher remains available only when invoked explicitly:

```bash
codex-safe
codex-safe exec "inspect this project"
```

`codex` remains the normal launcher and is not aliased to `codex-safe`.
Commands spawned by an explicit `codex-safe` session, its subagents, and the
`playwright_safe` MCP server receive the same per-session CloakBrowser CDP
endpoint.
MCP OAuth records persist in a dedicated encrypted keyring whose files and
unlock key are hidden from the jail. The host KDE Wallet is never mounted or
exposed over D-Bus.

Ordinary sessions expose separate, explicit browser servers. Use
`playwright_safe` for headless work:

```toml
[mcp_servers.playwright_safe]
command = "/home/USER/.local/bin/playwright-mcp-cloak"
args = ["--browser-mode=headless"]

[mcp_servers.playwright_safe_headed]
command = "/home/USER/.local/bin/playwright-mcp-cloak"
args = ["--browser-mode=headed"]
```

Replace `USER` with the account name because MCP command paths must be
absolute.
Headed mode opens a visible, focusable `CloakBrowser Automation` window on KDE.
Xephyr hosts that window while CloakBrowser runs on Xephyr's nested X display,
so the browser never receives the host X display. The installed KWin rule lets
the user focus the nested window for manual login, 2FA, typing, and paste.
A minimal window manager inside Xephyr tiles normal Chromium windows across the
display and focuses newly mapped browser windows.
A memory-only bridge mirrors KDE text clipboard changes into Xephyr and never
copies the nested clipboard back to KDE. Agents still use Playwright page tools
only and never inject host pointer or keyboard input.

Both modes remove display variables from the Playwright MCP process, disable
desktop D-Bus for the browser, and select Chromium's `basic` password backend
inside `~/.local/state/codex-safe/cloakbrowser-profile`. This dedicated `0700`
profile is the only persistent browser location and is protected by a
single-instance lock. Cookies and site storage survive restarts without KDE
Wallet access. The profile contains sensitive signed-in state and is protected
by filesystem permissions, not a desktop credential store. Restart Codex after
adding or changing either server.

The wrapper rejects unsafe launch roots, hard links whose inode counts prove an
external alias, missing sandbox controls, changed browser hashes, and
unavailable local CDP endpoints. Internal-only hard links are accepted. Run the
read-only doctor first, then the contained self-test when wanted:

```bash
~/.config/codex-safe/doctor.sh
~/.config/codex-safe/doctor.sh --run
~/.config/codex-safe/test-sandbox.sh
```

The payload README documents the exact filesystem boundary, browser attachment,
linked-worktree behavior, and explicit manifest-based uninstall operation.
