# codex-safe

`codex-safe` is a fail-closed Codex launcher for this Arch Linux workstation. It
uses Firejail as the mandatory outer boundary and Codex's supported legacy
Landlock workspace-write mode as an inner boundary. CloakBrowser, its patched
Chromium children, Playwright CLI, Playwright MCP, Codex MCP servers, and every
other descendant run inside the same Firejail instance.

## Launch

From a standalone repository or normal project directory:

```sh
codex-safe
codex-safe exec "your task"
codex-safe --search
```

`codex` remains the normal launcher and is not aliased to `codex-safe`. The
hardened launcher is used only when `codex-safe` is invoked explicitly. The
original executable is recorded by the
`~/.config/codex-safe/codex-original` symlink.

The launcher refuses `/`, `$HOME`, `/tmp`, `/var/tmp`, `/run`, any mount root,
unresolved paths and nested mounts. Multiply linked files are accepted when the
inode link count proves every alias is inside the workspace. If any alias is
external, a reviewed exception requires the explicit
`CODEX_SAFE_ALLOW_HARDLINKS=1` environment variable. Hard links alias an inode,
so editing a workspace pathname can still alter an external pathname that names
the same inode; Firejail path mounts cannot split that inode identity.

Git linked worktrees are detected. If their real gitdir lies outside the launch
directory it remains read-only. File editing works, but commits may fail; use a
standalone clone or disposable full repository when commits are required.

## Effective boundary

- Persistent writable roots: the one real launch directory plus the fixed
  `~/.local/state/codex-safe/cloakbrowser-profile` browser profile. The profile
  root is mode `0700`, rejects symlink redirection, and is guarded by a
  single-instance lock.
- Ephemeral writable roots: the Firejail-private `/tmp`, private `/dev`, and a
  fresh tmpfs mounted over the otherwise empty host directory
  `~/.cache/codex-safe-runtime`. Codex state and per-launch browser scratch data
  live on that tmpfs; the real host directory remains empty.
- Host `$HOME`, `/`, `/etc`, `/usr`, `/var`, `/opt`, `/srv`, `/boot`, `/mnt`,
  `/media`, and `/run/media` are read-only. Credential stores unrelated to Codex
  are blacklisted.
- `$HOME/.codex` is readable and read-only. Config and authentication are copied
  with mode `0600` into a per-session private `CODEX_HOME`; skills, plugins,
  packages, and vendor imports are linked read-only. Mutable Codex session
  databases, logs, and caches disappear on exit. Browser cookies and site
  storage remain only in the fixed browser profile.
- MCP OAuth records use a separate encrypted keyring under
  `~/.local/share/codex-safe/keyring`. A trusted broker runs outside the jail
  and exposes only a private per-session Secret Service socket. The keyring
  files and unlock key are blacklisted inside the jail, and the host KDE Wallet
  and user D-Bus remain inaccessible. The package's desktop user units are
  masked so KDE's `ksecretd` remains the normal desktop Secret Service.
- Firejail drops all capabilities, enables `nonewprivs`, seccomp, a private PID/
  IPC/device/tmp view, disables the host user/system D-Bus, and applies inherited
  Landlock write rules. Chromium may create its own *restricted* namespaces for
  its internal sandbox, but inherited Landlock and read-only mounts prevent a
  second namespace from recovering an external writable host view.
- Codex runtime overrides are locked to `workspace-write`, `on-request`, network
  enabled, `writable_roots=[]`, and `features.use_legacy_landlock=true`. The
  permanent `~/.codex/config.toml` is never weakened.

## Browser architecture

Each invocation chooses an unused random loopback port. A single 192-bit
fingerprint seed is generated when the private browser profile is initialized
and is reused with that profile so sites do not see every restart as a new
device. A non-blocking lock prevents two CloakBrowser processes from opening
the profile concurrently. `runtime-inner.sh` starts official `cloakserve` in
the same jail, with locale `en-IN`, timezone `Asia/Kolkata`, and auto-update
disabled. It waits at most 20 seconds, then verifies:

1. the listener is only `127.0.0.1`;
2. the browser executable is the pinned, verified CloakBrowser Chromium;
3. the generated fingerprint flag is present; and
4. the profile is inside its fixed private state directory.

Only then is Codex started. The environment exports `CLOAK_CDP_ENDPOINT`,
`PLAYWRIGHT_MCP_CDP_ENDPOINT`, `PLAYWRIGHT_MCP_CONFIG`,
`PLAYWRIGHT_MCP_OUTPUT_DIR`, and `CLOAKBROWSER_AUTO_UPDATE=false`. Official
Playwright CLI/MCP attach over CDP. Node and Python Playwright launch calls are
intercepted and attached to the same endpoint. The dynamic CDP and artifact
variables are also injected into Codex-spawned commands and the Playwright MCP
server, so delegated agents use the same browser session. Stock browser paths and
Playwright browser caches are hidden; failure never falls back to stock
Chromium. Screenshots, snapshots, traces, downloads, and output belong in
`<workspace>/.playwright-cli/`. An ordinary MCP session started directly in
`$HOME` is moved into the private
`~/.local/state/codex-safe/playwright-mcp-workspace/` fallback so Playwright MCP
never receives the entire home tree as its working directory.

Overrides are `CODEX_SAFE_LOCALE`, `CODEX_SAFE_TIMEZONE`,
`CODEX_SAFE_HEADED=true`, and `CODEX_SAFE_PROXY`. Headed mode opens a visible,
focusable Xephyr window named `CloakBrowser Automation` on KDE. Xephyr starts
outside the jail, while CloakBrowser inside the jail receives only the nested
display and a one-session authority cookie; Chromium never receives the host
display or host Xauthority. The user can type and paste into this window.
A private window manager tiles normal Chromium windows across Xephyr and gives
new browser windows keyboard focus.
A small bridge mirrors text from the KDE clipboard into Xephyr, but never
copies browser clipboard contents back to KDE. It retains clipboard text only
in memory and never writes or logs the payload. Automated interaction remains
Playwright/CDP-only and cannot inject host pointer or keyboard events.

Browser-side D-Bus is disabled and Chromium uses its `basic` password backend
only in the persistent private profile, preventing KDE Wallet prompts while
allowing browser cookies and site storage to survive restarts. Treat that
profile as sensitive local data: filesystem permissions protect it, but it is
not a replacement for an encrypted desktop credential store. Proxy credentials
are not logged, though Chromium necessarily receives proxy configuration in its
own process arguments.

## Operations

```sh
codex-safe-migrate-mcp
~/.config/codex-safe/doctor.sh
~/.config/codex-safe/doctor.sh --run
CODEX_SAFE_KEEP_TEST_REPO=1 ~/.config/codex-safe/test-sandbox.sh
~/.config/codex-safe/uninstall.sh
~/.config/codex-safe/uninstall.sh --purge
```

Run `codex-safe-migrate-mcp` once after installation to copy only the existing
Codex MCP OAuth records from the desktop Secret Service. Secret values move
through process pipes and are never printed or placed in a plaintext temporary
file. Future refreshes and logins persist in the dedicated keyring.

`playwright-cli` deliberately fails outside `codex-safe`. Search APIs can
discover sources and URLs, but their traffic is not claimed to pass through
CloakBrowser. CloakBrowser must not be used to bypass authentication, CAPTCHA,
paywalls, access controls, rate limits, robots directives, or legal restrictions.
Normal uninstall preserves browser sign-ins. The explicit `--purge` operation
removes the fixed browser profile and its saved sessions.
