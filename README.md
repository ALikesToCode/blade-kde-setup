# Blade KDE Setup

A reproducible Arch/Plasma 6 desktop built around a near-black surface, blue
accents, restrained green highlights, Candy icons, and rounded Klassy window
decorations. It captures the complete Blade KDE setup without storing account
tokens, private keys, host identity, or personal Git credentials.

The setup includes:

- Artix Dark Rounded Plasma global theme and color scheme
- Candy icon theme
- Klassy rounded decoration with compact pastel window controls
- Native, reliable Konsole tabs and a matching dark profile
- Coordinated 4K 16:10 and 3440×1440 ultrawide desktop wallpapers
- Matching Artix Material You SDDM login screen
- Bash, Git, Neovim, tmux, MPV, yt-dlp, aria2, Yay, and makepkg defaults
- Pacman parallel downloads and a weekly rate-tested Asian Reflector mirror list
- `updateall -y` for the package managers detected on the machine

## Install

Review the complete plan without changing the system:

```bash
./install.sh --dry-run --all
```

Install the full setup on an Arch-based KDE Plasma system:

```bash
./install.sh --all -y
```

The full install asks for `sudo` once. SDDM is deliberately not restarted, so
the new login screen appears safely after the next logout or reboot. Existing
files are copied to `~/.local/state/blade-kde-backups/` before replacement.

For only the unprivileged desktop and dotfiles, run:

```bash
./install.sh --user --apply
```

See [Installation](docs/INSTALL.md) for every mode and safety detail, and
[Components](docs/COMPONENTS.md) for the complete file map.

## Useful commands

```bash
./scripts/doctor.sh       # read-only prerequisite and installation report
./tests/smoke.sh          # syntax, manifest, portability, and secret checks
updateall --dry-run       # preview all detected package-manager updates
updateall -y              # update them with one sudo authentication
```

## Design notes

The desktop is intentionally solid rather than translucent or bubble-heavy.
KWin, Plasma, Konsole, and applications share the same dark visual foundation.
Konsole’s process-wide custom stylesheet remains disabled because native Qt tabs
preserve correct focus, clicking, close buttons, and multi-window behavior.

The wallpapers are original generated artwork exported at native sizes for both
displays. Login and desktop images form a smooth visual sequence while remaining
distinct.

## Platform

Tested on Arch Linux with KDE Plasma 6 on Wayland. The user-only files are mostly
portable, but package and system modes intentionally target Pacman, Yay, systemd,
Reflector, and SDDM.

## License and credits

This repository is distributed under GPL-3.0; bundled third-party assets retain
their own notices. See [Credits](CREDITS.md).
