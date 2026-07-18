# Installation

## Recommended flow

Run the doctor, preview every action, then install:

```bash
./scripts/doctor.sh
./install.sh --dry-run --all
./install.sh --all -y
```

The installer is idempotent: files that already match are skipped. Before a
different user file or system file is replaced, its current version is copied to
a timestamped directory under:

```text
~/.local/state/blade-kde-backups/
```

## Modes

`./install.sh` with no mode is equivalent to `--user --apply`.

| Mode | Effect | Privilege |
|---|---|---|
| `--user` | Dotfiles, commands, launcher artwork, icons, wallpapers, Konsole, Klassy preset, and local theme assets | User |
| `--apply` | Activates the appearance, wallpapers, and safe multi-display panel/widget layout | User |
| `--packages` | Installs `packages/pacman.txt`, then `packages/aur.txt` through Yay | Sudo for Pacman |
| `--system` | Tunes Pacman, installs Reflector settings, enables its timer, and installs SDDM | Sudo |
| `--all` | Runs packages, tools, user files, system tuning, and live KDE apply | Mixed |
| `--hardened` | Stages and integrates the optional verified workspace/browser launcher | User, after documented prerequisites |
| `--tools` | Installs pinned OpenWiki and OfficeCLI commands plus the Codex skill collection | Sudo for global npm; skills are user-local |

Add `--dry-run` to any combination for a no-change preview. Add `-y` to use
non-interactive package-manager confirmation.

## System changes

The system mode makes four bounded changes:

1. Sets `ParallelDownloads = 15` in `/etc/pacman.conf`. The rest of Pacman’s
   configuration is preserved.
2. Installs `system/reflector.conf` and enables `reflector.timer`. The list is
   restricted to recent HTTPS mirrors in India and nearby high-throughput Asian
   regions, then sorted by measured rate.
3. Installs `artix-material-you` below `/usr/share/sddm/themes/`.
4. Selects that theme through `/etc/sddm.conf.d/zz-artix-qylock.conf`.

The installer does not restart SDDM or terminate the current Plasma session.

After a Plasma or KWin package upgrade, log out and back in (or reboot) before
restarting only `plasmashell`. A newly loaded shell cannot safely use an older
in-memory Wayland compositor when their protocol generation changed. The doctor
detects this session/package mismatch on Arch systems.

## Panel safety

Normal installation uses the non-destructive panel mode: one panel per display
is configured and missing widgets are added, while unrelated panels and
existing pinned launchers remain intact. Plasma's applet configuration is
backed up before the live change. Exact panel replacement requires the separate
explicit command documented in [Plasma panels](PANELS.md).

## Package notes

Klassy is installed from the AUR, so Yay must already be available for the
`--packages` mode to install it automatically. If Yay is absent, the installer
finishes the official package list and prints the remaining manual action.

The Klassy preset records the version it was built with. A future incompatible
Klassy release may reject the import; the installer does not force an invalid
preset into a newer version. Open **System Settings → Colors & Themes → Window
Decorations** and load `Artix Dark Rounded` after reviewing it.

The package manifest installs Node.js, npm, and pnpm. User setup then installs
the current Wrangler v4 CLI into `PNPM_HOME`. Interactive Bash maps `npm` to
`pnpm` and `npx` to `pnpm dlx`; use `npm-system` or `npx-system` whenever a tool
specifically requires the Arch npm executable.

The `--tools` mode installs `openwiki@0.2.0` with npm, a checksum-verified
OfficeCLI v1.0.138 binary, and pinned personal Codex skills under
`~/.agents/skills/`. The collection includes OfficeCLI, all seven Caveman
skills, Matt Pocock's 22 maintained engineering/productivity skills, Hallmark's
complete design reference library, all canonical ECC skills, Karpathy's coding
guidelines, all six Emil Kowalski design-engineering skills, seven Code Review
Graph workflows, and all 263 Agency Agents as native Codex custom agents. The
Code Review Graph CLI is installed through uv, registered as a global Codex MCP
server without a fixed project working directory, and wired into additive
global Codex lifecycle hooks. Exact
repository commits live in `packages/codex-skills.lock`; deprecated,
in-progress, and author-personal Matt directories are deliberately excluded.
ECC's Claude hooks, translated duplicates, MCP mutations, and experimental
plugin wrapper are also excluded because direct Agent Skills are its reliable
Codex path. Re-run `./install.sh --tools` to restore or update the pinned set,
then restart Codex so it discovers new skills.

OpenWiki's only allowed npm lifecycle build is its required native
`better-sqlite3` dependency; npm scripts for other dependencies remain blocked.

User setup also installs the global development policy after backing up an
existing version. It requires modular changes, focused verification, independent
commits, preservation of the configured Git/GitHub identity, and explicit
approval before destructive work. The Bash profile maps both `vi` and `vim` to
the included Neovim configuration when `nvim` is available.

The hardened mode is deliberately excluded from `--all`. It fails closed when
its pinned browser, source launcher, Playwright tools, ShellCheck binary, or
Firejail allow-list is missing. Follow [Hardened workspace](HARDENED-WORKSPACE.md)
before selecting it.

## Restore

Each changed destination is mirrored inside its timestamped backup directory.
Copy the wanted file or directory back to the same absolute path. System files
need `sudo`. For SDDM, restoring the previous file in `/etc/sddm.conf.d/` is
enough; no display-manager restart is required until you are ready to log out.
