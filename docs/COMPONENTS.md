# Components

| Area | Repository source | Installed destination |
|---|---|---|
| Plasma global theme | `kde/look-and-feel/` | `~/.local/share/plasma/look-and-feel/` |
| KDE colors | `kde/color-schemes/` | `~/.local/share/color-schemes/` |
| Candy icons | `assets/icons/candy-icons/` | `~/.local/share/icons/candy-icons/` |
| Klassy preset | `kde/klassy/` | `~/.local/share/klassy/` and `~/.config/klassy/` |
| Konsole | `kde/konsole/` | `~/.local/share/konsole/` and `~/.config/konsolerc` keys |
| Desktop wallpapers | `assets/wallpapers/desktop/` | `~/.local/share/wallpapers/BladeKDE/desktop/` |
| SDDM artwork | `assets/wallpapers/login/` | `/usr/share/sddm/themes/artix-material-you/` |
| SDDM interface | `kde/sddm/artix-material-you/` | Local Qylock assets and system SDDM theme |
| Shell | `dotfiles/bash/` | `~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.inputrc` |
| Media | `dotfiles/media/` | `~/.config/mpv/` and `~/.config/yt-dlp/` |
| Editors/tools | `dotfiles/nvim/`, `dotfiles/tmux/` | `~/.config/nvim/init.lua`, `~/.tmux.conf` |
| Download tuning | `dotfiles/downloads/` | `~/.aria2/aria2.conf`, `~/.makepkg.conf` |
| Safe Git defaults | `dotfiles/git/` | Included from the user’s existing global Git config |
| Package updater | `bin/` | `~/.local/bin/updateall` and `update-all-packages` |
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
- caches, browser profiles, application databases, and histories
- wallpaper generation masters and temporary image outputs
- the previous process-wide Konsole stylesheet activation that caused mouse and
  tab-focus problems
