#!/usr/bin/env bash

# Read-only prerequisite and installation check.

set -u

failures=0
warnings=0

ok() { printf '  [ok] %s\n' "$*"; }
warn() { printf '  [--] %s\n' "$*"; warnings=$((warnings + 1)); }
bad() { printf '  [!!] %s\n' "$*"; failures=$((failures + 1)); }

printf 'Blade KDE doctor\n\nCommands\n'
for command in pacman kwriteconfig6 plasma-apply-lookandfeel qdbus6 konsole mpv git; do
    if command -v "$command" >/dev/null 2>&1; then
        ok "$command"
    else
        bad "$command is missing"
    fi
done

for command in yay klassy-settings reflector node pnpm wrangler; do
    if command -v "$command" >/dev/null 2>&1; then
        ok "$command"
    else
        warn "$command is optional or not installed yet"
    fi
done
if command -v qmllint6 >/dev/null 2>&1 || command -v qmllint >/dev/null 2>&1; then
    ok 'QML validator'
else
    warn 'qmllint is optional or not installed yet'
fi

printf '\nUser assets\n'
declare -a assets=(
    "$HOME/.local/share/color-schemes/ArtixDarkRounded.colors"
    "$HOME/.local/share/plasma/desktoptheme/artix-dark-rounded/metadata.json"
    "$HOME/.local/share/icons/candy-icons/index.theme"
    "$HOME/.local/share/konsole/Artix Dark Rounded.profile"
    "$HOME/.local/share/klassy/Artix_Dark_Rounded.klpw"
    "$HOME/.local/share/wallpapers/BladeKDE/desktop/desktop-16x10-3840x2400.png"
    "$HOME/.local/share/blade-kde/branding/launcher/a-candy-icon.png"
)
for asset in "${assets[@]}"; do
    if [[ -e $asset ]]; then ok "${asset/#$HOME/~}"; else warn "missing: ${asset/#$HOME/~}"; fi
done

printf '\nSystem settings\n'
if [[ -r /etc/pacman.conf ]] && grep -Eq '^[[:space:]]*ParallelDownloads[[:space:]]*=[[:space:]]*15' /etc/pacman.conf; then
    ok 'Pacman ParallelDownloads = 15'
else
    warn 'Pacman parallel download tuning is not installed'
fi
if systemctl is-enabled reflector.timer >/dev/null 2>&1 \
   || [[ -L /etc/systemd/system/timers.target.wants/reflector.timer ]]; then
    ok 'Reflector timer is enabled'
else
    warn 'Reflector timer is not enabled'
fi
if [[ -r /etc/sddm.conf.d/zz-artix-qylock.conf ]]; then
    ok 'Artix Material You SDDM configuration'
else
    warn 'SDDM login theme is not installed system-wide'
fi

printf '\nResult: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
((failures == 0))
