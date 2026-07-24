# Components

| Area | Repository source | Installed destination |
|---|---|---|
| Plasma global theme | `kde/look-and-feel/` | `~/.local/share/plasma/look-and-feel/` |
| Plasma surface palette | `kde/desktoptheme/artix-dark-rounded/` | Optional palette asset; stable Breeze Dark supplies the selected popup/widget SVG set |
| KDE colors | `kde/color-schemes/` | `~/.local/share/color-schemes/` |
| Candy icons | `assets/icons/candy-icons/` | `~/.local/share/icons/candy-icons/` |
| Launcher artwork | `assets/branding/launcher/` | Blade branding data and freedesktop hicolor icon sizes |
| Plasma panels/widgets | `kde/plasma/`, `scripts/apply-panels.sh` | One native application/status panel per display |
| Material Event Calendar | `extras/eventcalendar/`, `scripts/install-event-calendar.sh` | Pinned Plasma 6 Event Calendar with Blade theme overlay and recurring iCalendar support |
| Blade desktop clock | `kde/plasma/plasmoids/org.mysterious.bladeclock/`, `scripts/apply-desktop-clock.sh` | SDDM-inspired live clock on every desktop containment |
| Klassy preset | `kde/klassy/` | `~/.local/share/klassy/` and `~/.config/klassy/` |
| Konsole | `kde/konsole/` | `~/.local/share/konsole/` and `~/.config/konsolerc` keys |
| Desktop wallpapers | `assets/wallpapers/desktop/` | `~/.local/share/wallpapers/BladeKDE/desktop/` |
| SDDM artwork | `assets/wallpapers/login/` | `/usr/share/sddm/themes/artix-material-you/` |
| SDDM interface | `kde/sddm/artix-material-you/` | Local Qylock assets, quick-setting icons, and system SDDM theme |
| Shell | `dotfiles/bash/` | `~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.inputrc` |
| Node/Cloudflare CLI | `dotfiles/bash/`, `packages/pacman.txt` | pnpm-first aliases and `~/.local/share/pnpm/bin/wrangler` |
| Codex tools/skills | `packages/codex-skills.lock`, `packages/codex-agents.lock`, `packages/npm-global.txt`, `packages/python-tools.lock`, `scripts/install-codex-tools.sh` | OpenWiki, OfficeCLI, Caveman, Matt Pocock, Hallmark, ECC, Karpathy, Emil Kowalski, Agency Agents, and Code Review Graph |
| Media | `dotfiles/media/` | `~/.config/mpv/` and `~/.config/yt-dlp/` |
| Editors/tools | `dotfiles/nvim/`, `dotfiles/tmux/` | `~/.config/nvim/init.lua`, `~/.tmux.conf` |
| Development policy | `dotfiles/agents/AGENTS.md` | Global engineering, verification, Git, and safety instructions |
| Download tuning | `dotfiles/downloads/` | `~/.aria2/aria2.conf`, `~/.makepkg.conf` |
| Safe Git defaults | `dotfiles/git/` | Included from the user’s existing global Git config |
| Package updater | `bin/` | `~/.local/bin/updateall` and `update-all-packages` |
| Optimized app launchers | `dotfiles/apps/` | Native Wayland and integrated Candy controls for Zen, Wayland Antigravity, and Vulkan-pinned Zed |
| Hardened workspace launcher | `extras/hardened-workspace/` | Optional fail-closed Firejail/Landlock runtime and browser wrappers |
| Package manifests | `packages/` | Consumed by `install.sh --packages` |
| Mirror tuning | `system/reflector.conf` | `/etc/xdg/reflector/reflector.conf` |

## Palette

The visual base is `#05070a`, with dark raised surfaces around `#0d1117` and
`#141b24`. Blue is the primary accent; green is a secondary success/highlight
color. Window buttons use pastel yellow, green, and coral only on hover or press,
keeping the normal title bar calm and cohesive.

## Deliberately excluded

- `.env` files, API tokens, SSH/GPG keys, and credential stores
- GitHub authentication and personal Git identity
- caches, browser data, application databases, and histories; the single Zen
  integrated-titlebar preference is merged without copying profile data
- wallpaper generation masters and temporary image outputs
- the previous process-wide Konsole stylesheet activation that caused mouse and
  tab-focus problems
- CloakBrowser binaries, Playwright dependencies, mutable sandbox state, and
  verification scratch repositories; only checksummed policy/configuration and
  installers are tracked
