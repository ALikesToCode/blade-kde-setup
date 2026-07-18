#!/usr/bin/env bash

set -Eeuo pipefail

failures=0
check() {
    local label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '  [ok] %s\n' "$label"
    else
        printf '  [!!] %s\n' "$label" >&2
        failures=$((failures + 1))
    fi
}

printf 'Blade application launcher check\n'
check 'Zen wrapper' "$HOME/.local/bin/zen-browser" --version
check 'Antigravity Wayland flags' grep -Fxq -- '--ozone-platform=wayland' \
    "$HOME/.config/antigravity-flags.conf"
# Electron can abort during --version when no graphical sandbox is available;
# launch behavior is covered by the flags file, so verify the installed target
# without starting the GUI in this read-only check.
check 'Antigravity executable path' test -x /usr/bin/antigravity
check 'Zed wrapper' "$HOME/.local/bin/zeditor" --version
check 'Zen desktop override' grep -Fq "$HOME/.local/bin/zen-browser" \
    "$HOME/.local/share/applications/zen.desktop"
check 'Zed desktop override' grep -Fq "$HOME/.local/bin/zeditor" \
    "$HOME/.local/share/applications/dev.zed.Zed.desktop"

if command -v desktop-file-validate >/dev/null 2>&1; then
    check 'Desktop entry syntax' desktop-file-validate \
        "$HOME/.local/share/applications/zen.desktop" \
        "$HOME/.local/share/applications/dev.zed.Zed.desktop"
fi

printf '\nResult: %d failure(s).\n' "$failures"
((failures == 0))
