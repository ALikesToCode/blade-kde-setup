#!/usr/bin/env bash

# Apply the Blade multi-display Plasma layout without deleting panels by default.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=0
REPLACE_EXISTING=0
CONFIRM_REPLACE=0
GPU_PREFIX=${BLADE_GPU_SENSOR_PREFIX:-gpu/gpu1}
GPU_TITLE=${BLADE_GPU_TITLE:-RTX 5090 GPU}
ICON_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/blade-kde/branding/launcher/a-candy-icon.png"

usage() {
    cat <<'EOF'
Usage: ./scripts/apply-panels.sh [options]

By default, updates one existing panel per display and adds missing Blade
widgets. It does not remove panels or duplicate widgets.

Options:
  -n, --dry-run        Print the intended layout without changing Plasma
  --replace-existing   Back up and replace every panel with the exact layout
  -y, --yes            Required acknowledgement for --replace-existing
  -h, --help           Show this help

Environment:
  BLADE_GPU_SENSOR_PREFIX  Plasma sensor prefix (default: gpu/gpu1)
  BLADE_GPU_TITLE          GPU donut title (default: RTX 5090 GPU)
EOF
}

while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        --replace-existing) REPLACE_EXISTING=1 ;;
        -y|--yes) CONFIRM_REPLACE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'apply-panels: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if ((REPLACE_EXISTING && !CONFIRM_REPLACE)); then
    printf 'apply-panels: --replace-existing also requires --yes because it removes current panels.\n' >&2
    exit 2
fi

for value in "$GPU_PREFIX" "$GPU_TITLE" "$ICON_PATH"; do
    [[ $value != *$'\n'* && $value != *$'\r'* ]] || {
        printf 'apply-panels: runtime values may not contain newlines.\n' >&2
        exit 2
    }
done

if ((DRY_RUN)); then
    printf 'Blade Plasma panel plan:\n'
    printf '  mode: %s\n' "$([[ $REPLACE_EXISTING == 1 ]] && printf exact-replacement || printf safe-ensure)"
    printf '  primary: bottom, 46px, floating, opaque, always visible\n'
    printf '  additional displays: same application panel, auto-hide on hover edge\n'
    printf '  widgets: launcher, tasks, media, CPU/RAM/GPU donuts, workspaces, status, calendar clock\n'
    printf '  status: Wi-Fi, Bluetooth, audio, battery, notifications\n'
    printf '  accent: blue primary with green telemetry highlight\n'
    exit 0
fi

QDBUS=
if command -v qdbus6 >/dev/null 2>&1; then
    QDBUS=qdbus6
elif command -v qdbus >/dev/null 2>&1; then
    QDBUS=qdbus
else
    printf 'apply-panels: qdbus6 is required (install qt6-tools).\n' >&2
    exit 1
fi

if [[ ! -f $ICON_PATH ]]; then
    printf 'apply-panels: launcher artwork is not installed at %s. Run ./install.sh --user first.\n' "$ICON_PATH" >&2
    exit 1
fi

escape_js() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

config="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
if [[ -f $config ]]; then
    backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/$(date +%Y%m%d-%H%M%S)/home/${USER:-user}/.config"
    mkdir -p -- "$backup_dir"
    cp -a -- "$config" "$backup_dir/plasma-org.kde.plasma.desktop-appletsrc"
    printf 'Backed up the existing Plasma layout to %s\n' "$backup_dir"
fi

script=$(printf 'var BLADE_ICON_PATH = "%s";\nvar BLADE_GPU_PREFIX = "%s";\nvar BLADE_GPU_TITLE = "%s";\nvar BLADE_REPLACE_EXISTING = %s;\n' \
    "$(escape_js "$ICON_PATH")" \
    "$(escape_js "$GPU_PREFIX")" \
    "$(escape_js "$GPU_TITLE")" \
    "$([[ $REPLACE_EXISTING == 1 ]] && printf true || printf false)")
script+=$(<"$ROOT/kde/plasma/blade-panels.js")

if ! output=$($QDBUS org.kde.plasmashell /PlasmaShell \
    org.kde.PlasmaShell.evaluateScript "$script" 2>&1); then
    printf 'apply-panels: Plasma is not reachable in this session: %s\n' "$output" >&2
    exit 1
fi

[[ -n $output ]] && printf '%s\n' "$output"
printf 'Blade panels are configured. Additional displays use auto-hide.\n'
