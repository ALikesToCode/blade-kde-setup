#!/usr/bin/env bash

set -Eeuo pipefail
umask 077
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=0
ACTIVATE=0
for argument in "$@"; do
    case "$argument" in
        --dry-run) DRY_RUN=1 ;;
        --activate) ACTIVATE=1 ;;
        --help)
            printf 'Usage: %s [--dry-run] [--activate]\n' "$0"
            printf 'Install the power controls; --activate starts the user service and adds panel widgets.\n'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
    esac
done

DATA_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG_ROOT=${XDG_CONFIG_HOME:-$HOME/.config}
BACKUP_ROOT=${BLADE_BACKUP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/power-$(date +%Y%m%d-%H%M%S-%N)}

copy_file() {
    local source=$1 target=$2 mode=${3:-644}
    if [[ -f $target ]] && cmp -s -- "$source" "$target"; then
        return
    fi
    if ((DRY_RUN)); then
        printf 'Would install %s -> %s\n' "$source" "$target"
        return
    fi
    [[ ! -L $target ]] || { printf 'Refusing symlink target: %s\n' "$target" >&2; exit 1; }
    if [[ -e $target ]]; then
        local backup="$BACKUP_ROOT/${target#/}"
        [[ ! -e $backup ]] || { printf 'Backup already exists: %s\n' "$backup" >&2; exit 1; }
        mkdir -p -- "$(dirname -- "$backup")"
        cp -a -- "$target" "$backup"
    fi
    mkdir -p -- "$(dirname -- "$target")"
    install -m "$mode" -- "$source" "$target"
}

copy_file "$ROOT/bin/blade-power" "$HOME/.local/bin/blade-power" 755
for source in "$ROOT"/lib/blade_power/*.py; do
    copy_file "$source" "$DATA_ROOT/blade-kde/lib/blade_power/${source##*/}"
done
copy_file "$ROOT/dotfiles/systemd/user/blade-power.service" "$CONFIG_ROOT/systemd/user/blade-power.service"
if [[ ! -e $CONFIG_ROOT/blade-power.conf ]]; then
    copy_file "$ROOT/dotfiles/power/blade-power.conf" "$CONFIG_ROOT/blade-power.conf" 600
fi
plasmoid=org.mysterious.bladepower
copy_file "$ROOT/kde/plasma/plasmoids/$plasmoid/metadata.json" "$DATA_ROOT/plasma/plasmoids/$plasmoid/metadata.json"
copy_file "$ROOT/kde/plasma/plasmoids/$plasmoid/contents/ui/main.qml" "$DATA_ROOT/plasma/plasmoids/$plasmoid/contents/ui/main.qml"
copy_file "$ROOT/kde/plasma/power-controls.js" "$DATA_ROOT/blade-kde/power-controls.js"

if ((ACTIVATE)); then
    # Preserve the active Artix theme when the native brightness widget enters dark mode.
    if command -v kreadconfig6 >/dev/null && \
        [[ $(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage) == org.mysterious.artixdarkrounded.desktop ]]; then
        if ((DRY_RUN)); then
            printf 'Would set the Dark Mode target to Artix Dark Rounded.\n'
        else
            kwriteconfig6 --file kdeglobals --group KDE --key DefaultDarkLookAndFeel --notify org.mysterious.artixdarkrounded.desktop
        fi
    fi
    if ((DRY_RUN)); then
        printf 'Would start blade-power.service and add Brightness and Blade Power to existing application panels.\n'
        exit 0
    fi
    for executable in python3 qdbus6 powerprofilesctl systemctl; do
        command -v "$executable" >/dev/null || {
            printf 'Missing %s. Install prerequisites: sudo pacman -S --needed python qt6-tools powerdevil power-profiles-daemon plasma5support\n' "$executable" >&2
            exit 1
        }
    done
    layout="$CONFIG_ROOT/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ -f $layout ]]; then
        mkdir -p -- "$BACKUP_ROOT"
        cp -a -- "$layout" "$BACKUP_ROOT/plasma-org.kde.plasma.desktop-appletsrc"
        printf 'Panel backup: %s/plasma-org.kde.plasma.desktop-appletsrc\n' "$BACKUP_ROOT"
    fi
    systemctl --user daemon-reload
    systemctl --user enable --now blade-power.service
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "$(<"$DATA_ROOT/blade-kde/power-controls.js")"
    printf 'Blade Power is active. Unknown external chargers use the USB-C saving settings.\n'
fi
