#!/usr/bin/env bash

# Add the Blade SDDM-inspired clock to every Plasma desktop containment.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=0
[[ ${1:-} == --dry-run ]] && DRY_RUN=1

PLUGIN_ID=org.mysterious.bladeclock
PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$PLUGIN_ID"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"

if ((DRY_RUN)); then
    printf 'Blade desktop clock plan:\n'
    printf '  widget: %s\n' "$PLUGIN_ID"
    printf '  placement: upper-left visual field on every display\n'
    printf '  behavior: add missing instances; preserve existing positions\n'
    printf '  palette: blue hour, green minutes, dark date pill\n'
    exit 0
fi

[[ -f $PLUGIN_DIR/metadata.json && -f $PLUGIN_DIR/contents/ui/main.qml ]] || {
    printf 'apply-desktop-clock: install the Blade clock plasmoid first with ./install.sh --user.\n' >&2
    exit 1
}

if command -v qdbus6 >/dev/null 2>&1; then
    QDBUS=qdbus6
elif command -v qdbus >/dev/null 2>&1; then
    QDBUS=qdbus
else
    printf 'apply-desktop-clock: qdbus6 is required (install qt6-tools).\n' >&2
    exit 1
fi

if [[ -f $CONFIG ]]; then
    backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/$(date +%Y%m%d-%H%M%S)/home/${USER:-user}/.config"
    mkdir -p -- "$backup_dir"
    cp -a -- "$CONFIG" "$backup_dir/plasma-org.kde.plasma.desktop-appletsrc"
    printf 'Backed up the existing Plasma layout to %s\n' "$backup_dir"
fi

script=$(<"$ROOT/kde/plasma/blade-desktop-clock.js")
if ! output=$($QDBUS org.kde.plasmashell /PlasmaShell \
    org.kde.PlasmaShell.evaluateScript "$script" 2>&1); then
    printf 'apply-desktop-clock: Plasma is not reachable in this session: %s\n' "$output" >&2
    exit 1
fi

[[ -n $output ]] && printf '%s\n' "$output"
printf 'Blade desktop clock is configured on every display.\n'
