#!/usr/bin/env bash

# Reproduce the Blade KDE desktop without replacing unrelated user settings.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
ASSUME_YES=0
DO_USER=0
DO_APPLY=0
DO_PACKAGES=0
DO_SYSTEM=0
MODE_SELECTED=0
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/$(date +%Y%m%d-%H%M%S)"
SUDO_KEEPALIVE_PID=

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

With no mode flag, installs the user configuration and applies the KDE theme.

Modes:
  --all          Packages + user files + system tuning + live KDE setup
  --user         Install home-directory files and desktop assets
  --apply        Apply the installed KDE appearance to the current session
  --packages     Install the Arch and AUR package manifests
  --system       Configure Pacman, Reflector, and the SDDM login theme

Options:
  -n, --dry-run  Print the plan without changing anything or asking for sudo
  -y, --yes      Use non-interactive package confirmation
  -h, --help     Show this help

Examples:
  ./install.sh --dry-run --all
  ./install.sh --all -y
  ./install.sh --user --apply
EOF
}

while (($#)); do
    case $1 in
        --all)
            DO_USER=1; DO_APPLY=1; DO_PACKAGES=1; DO_SYSTEM=1; MODE_SELECTED=1
            ;;
        --user) DO_USER=1; MODE_SELECTED=1 ;;
        --apply) DO_APPLY=1; MODE_SELECTED=1 ;;
        --packages) DO_PACKAGES=1; MODE_SELECTED=1 ;;
        --system) DO_SYSTEM=1; MODE_SELECTED=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'blade-kde: unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if ((MODE_SELECTED == 0)); then
    DO_USER=1
    DO_APPLY=1
fi

if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
    BLUE=$'\033[38;2;138;180;248m'
    GREEN=$'\033[38;2;129;201;149m'
    YELLOW=$'\033[38;2;253;214;99m'
    RED=$'\033[38;2;242;139;130m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    BLUE= GREEN= YELLOW= RED= BOLD= RESET=
fi

section() { printf '\n%s%s==>%s %s\n' "$BOLD" "$BLUE" "$RESET" "$*"; }
info() { printf '  %s•%s %s\n' "$BLUE" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '%sblade-kde: %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

print_command() {
    local arg
    printf '  $'
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
}

run() {
    if ((DRY_RUN)); then
        print_command "$@"
    else
        "$@"
    fi
}

declare -A BACKED_UP=()

backup_target() {
    local target=$1 relative
    [[ -e $target || -L $target ]] || return 0
    [[ ${BACKED_UP[$target]+yes} ]] && return 0
    BACKED_UP["$target"]=1
    relative=${target#/}
    if ((DRY_RUN)); then
        printf '  backup %q -> %q\n' "$target" "$BACKUP_ROOT/$relative"
        return 0
    fi
    mkdir -p -- "$(dirname -- "$BACKUP_ROOT/$relative")"
    cp -a -- "$target" "$BACKUP_ROOT/$relative"
}

same_tree() {
    [[ -d $2 ]] && diff -qr --no-dereference "$1" "$2" >/dev/null 2>&1
}

install_file() {
    local source=$1 target=$2 mode=${3:-0644}
    if [[ -f $target ]] && cmp -s -- "$source" "$target"; then
        ((DRY_RUN)) || chmod "$mode" "$target" 2>/dev/null || true
        info "Unchanged: ${target/#$HOME/~}"
        return 0
    fi
    backup_target "$target"
    run mkdir -p -- "$(dirname -- "$target")"
    run install -m "$mode" -- "$source" "$target"
}

install_template() {
    local source=$1 target=$2 mode=${3:-0644} temporary
    if ((DRY_RUN)); then
        backup_target "$target"
        printf '  render %q -> %q\n' "$source" "$target"
        return 0
    fi
    temporary=$(mktemp)
    sed "s|__HOME__|${HOME//&/\\&}|g" "$source" > "$temporary"
    install_file "$temporary" "$target" "$mode"
    rm -f -- "$temporary"
}

install_tree() {
    local source=$1 target=$2
    if same_tree "$source" "$target"; then
        info "Unchanged: ${target/#$HOME/~}/"
        return 0
    fi
    backup_target "$target"
    run mkdir -p -- "$target"
    run cp -a -- "$source/." "$target/"
}

cleanup() {
    if [[ -n ${SUDO_KEEPALIVE_PID:-} ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

begin_sudo_session() {
    ((DRY_RUN)) && return 0
    command -v sudo >/dev/null 2>&1 || die 'sudo is required for --packages and --system.'
    info 'Authenticating once for system-level changes'
    sudo -v
    (
        while sleep 45; do
            sudo -n -v >/dev/null 2>&1 || exit
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
}

install_user_files() {
    section 'Installing user configuration and desktop assets'

    install_file "$ROOT/dotfiles/bash/bashrc" "$HOME/.bashrc"
    install_file "$ROOT/dotfiles/bash/bash_profile" "$HOME/.bash_profile"
    install_file "$ROOT/dotfiles/bash/profile" "$HOME/.profile"
    install_file "$ROOT/dotfiles/bash/inputrc" "$HOME/.inputrc"
    install_template "$ROOT/dotfiles/downloads/aria2/aria2.conf" "$HOME/.aria2/aria2.conf"
    install_file "$ROOT/dotfiles/downloads/makepkg.conf" "$HOME/.makepkg.conf"
    install_template "$ROOT/dotfiles/media/mpv/mpv.conf" "$HOME/.config/mpv/mpv.conf"
    install_file "$ROOT/dotfiles/media/mpv/input.conf" "$HOME/.config/mpv/input.conf"
    install_file "$ROOT/dotfiles/media/yt-dlp/config" "$HOME/.config/yt-dlp/config"
    install_file "$ROOT/dotfiles/nvim/init.lua" "$HOME/.config/nvim/init.lua"
    install_file "$ROOT/dotfiles/tmux/tmux.conf" "$HOME/.tmux.conf"
    install_file "$ROOT/bin/update-all-packages" "$HOME/.local/bin/update-all-packages" 0755
    install_file "$ROOT/bin/updateall" "$HOME/.local/bin/updateall" 0755

    install_tree "$ROOT/kde/look-and-feel/org.mysterious.artixdarkrounded.desktop" \
        "$HOME/.local/share/plasma/look-and-feel/org.mysterious.artixdarkrounded.desktop"
    install_file "$ROOT/kde/color-schemes/ArtixDarkRounded.colors" \
        "$HOME/.local/share/color-schemes/ArtixDarkRounded.colors"
    install_tree "$ROOT/assets/icons/candy-icons" "$HOME/.local/share/icons/candy-icons"
    install_tree "$ROOT/assets/wallpapers" "$HOME/.local/share/wallpapers/BladeKDE"
    install_file "$ROOT/kde/konsole/Artix Dark Rounded.profile" \
        "$HOME/.local/share/konsole/Artix Dark Rounded.profile"
    install_file "$ROOT/kde/konsole/ArtixDarkRounded.colorscheme" \
        "$HOME/.local/share/konsole/ArtixDarkRounded.colorscheme"
    install_file "$ROOT/kde/konsole/artix-tab-close.svg" \
        "$HOME/.local/share/konsole/artix-tab-close.svg"
    install_template "$ROOT/kde/konsole/ArtixDarkRoundedTabs.qss" \
        "$HOME/.local/share/konsole/ArtixDarkRoundedTabs.qss"
    install_file "$ROOT/kde/klassy/Artix_Dark_Rounded.klpw" \
        "$HOME/.local/share/klassy/Artix_Dark_Rounded.klpw"
    install_file "$ROOT/kde/klassy/klassyrc" "$HOME/.config/klassy/klassyrc"
    install_file "$ROOT/kde/klassy/windecopresetsrc" "$HOME/.config/klassy/windecopresetsrc"

    install_tree "$ROOT/kde/sddm/artix-material-you" \
        "$HOME/.local/share/qylock/themes/artix-material-you"
    install_file "$ROOT/assets/wallpapers/login/login-ultrawide-3440x1440.png" \
        "$HOME/.local/share/qylock/themes/artix-material-you/login-ultrawide-3440x1440.png"
    install_file "$ROOT/assets/wallpapers/login/login-16x10-3840x2400.png" \
        "$HOME/.local/share/qylock/themes/artix-material-you/login-16x10-3840x2400.png"

    install_file "$ROOT/dotfiles/git/blade-kde.gitconfig" \
        "$HOME/.config/git/blade-kde.gitconfig"
    if ((DRY_RUN)); then
        printf '  ensure git include.path=%q\n' "$HOME/.config/git/blade-kde.gitconfig"
    elif command -v git >/dev/null 2>&1; then
        if ! git config --global --get-all include.path 2>/dev/null | grep -Fxq "$HOME/.config/git/blade-kde.gitconfig"; then
            git config --global --add include.path "$HOME/.config/git/blade-kde.gitconfig"
        fi
    else
        warn 'git is not installed; the safe Git defaults were copied but not included.'
    fi

    if ((DRY_RUN)); then
        printf '  merge maxconcurrentdownloads=8 into %q\n' "$HOME/.config/yay/config.json"
    elif command -v python3 >/dev/null 2>&1; then
        local yay_source="$ROOT/dotfiles/yay/config.json"
        local yay_target="$HOME/.config/yay/config.json"
        backup_target "$yay_target"
        mkdir -p -- "$(dirname -- "$yay_target")"
        python3 - "$yay_source" "$yay_target" <<'PY'
import json
import pathlib
import sys

source, target = map(pathlib.Path, sys.argv[1:])
desired = json.loads(source.read_text())
current = {}
if target.exists():
    try:
        current = json.loads(target.read_text())
    except (OSError, json.JSONDecodeError):
        pass
current["maxconcurrentdownloads"] = desired["maxconcurrentdownloads"]
target.write_text(json.dumps(current, indent=2) + "\n")
PY
    else
        warn 'python3 is unavailable; leaving the existing Yay configuration untouched.'
    fi

    if ((DRY_RUN)); then
        info "Backups would be stored below ${BACKUP_ROOT/#$HOME/~}"
    elif [[ -d $BACKUP_ROOT ]]; then
        info "Previous files backed up to ${BACKUP_ROOT/#$HOME/~}"
    fi
}

read_manifest() {
    local file=$1
    sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$file"
}

install_packages() {
    section 'Installing package manifests'
    if ! command -v pacman >/dev/null 2>&1; then
        if ((DRY_RUN)); then
            warn 'pacman is not present here; showing the Arch package plan anyway.'
        else
            die 'This package manifest targets Arch-based systems (pacman was not found).'
        fi
    fi

    local -a packages aur_packages pacman_command yay_command
    mapfile -t packages < <(read_manifest "$ROOT/packages/pacman.txt")
    mapfile -t aur_packages < <(read_manifest "$ROOT/packages/aur.txt")
    pacman_command=(sudo pacman -Syu --needed)
    ((ASSUME_YES)) && pacman_command+=(--noconfirm)
    pacman_command+=("${packages[@]}")
    run "${pacman_command[@]}"

    if ((${#aur_packages[@]})); then
        if command -v yay >/dev/null 2>&1 || ((DRY_RUN)); then
            yay_command=(yay -S --needed)
            ((ASSUME_YES)) && yay_command+=(--noconfirm --answerclean None --answerdiff None --answeredit None)
            yay_command+=("${aur_packages[@]}")
            run "${yay_command[@]}"
        else
            warn 'yay is not installed. Install the AUR manifest manually: klassy'
        fi
    fi
}

backup_system_target() {
    local target=$1 relative
    [[ -e $target || -L $target ]] || return 0
    relative="system/${target#/}"
    if ((DRY_RUN)); then
        printf '  backup %q -> %q\n' "$target" "$BACKUP_ROOT/$relative"
        return 0
    fi
    mkdir -p -- "$(dirname -- "$BACKUP_ROOT/$relative")"
    sudo cp -a -- "$target" "$BACKUP_ROOT/$relative"
    sudo chown -R "$(id -u):$(id -g)" "$BACKUP_ROOT/system"
}

configure_system() {
    section 'Configuring fast downloads, mirrors, and SDDM'

    if [[ -f /etc/pacman.conf ]]; then
        backup_system_target /etc/pacman.conf
        if ((DRY_RUN)); then
            printf '  set ParallelDownloads = 15 in /etc/pacman.conf\n'
        else
            local pacman_temp
            pacman_temp=$(mktemp)
            awk '
                BEGIN { done = 0 }
                /^[[:space:]#]*ParallelDownloads[[:space:]]*=/ {
                    if (!done) print "ParallelDownloads = 15"
                    done = 1
                    next
                }
                { print }
                END { if (!done) print "ParallelDownloads = 15" }
            ' /etc/pacman.conf > "$pacman_temp"
            sudo install -m 0644 -- "$pacman_temp" /etc/pacman.conf
            rm -f -- "$pacman_temp"
        fi
    else
        warn '/etc/pacman.conf does not exist; skipping Pacman tuning.'
    fi

    backup_system_target /etc/xdg/reflector/reflector.conf
    run sudo install -d -m 0755 /etc/xdg/reflector
    run sudo install -m 0644 "$ROOT/system/reflector.conf" /etc/xdg/reflector/reflector.conf
    if command -v systemctl >/dev/null 2>&1; then
        run sudo systemctl enable --now reflector.timer
    else
        warn 'systemctl was not found; Reflector was configured but its timer was not enabled.'
    fi

    local sddm_theme=/usr/share/sddm/themes/artix-material-you
    backup_system_target "$sddm_theme"
    run sudo install -d -m 0755 "$sddm_theme"
    run sudo install -m 0644 "$ROOT/kde/sddm/artix-material-you/Main.qml" "$sddm_theme/Main.qml"
    run sudo install -m 0644 "$ROOT/kde/sddm/artix-material-you/metadata.desktop" "$sddm_theme/metadata.desktop"
    run sudo install -m 0644 "$ROOT/kde/sddm/artix-material-you/theme.conf" "$sddm_theme/theme.conf"
    run sudo install -m 0644 "$ROOT/assets/wallpapers/login/login-ultrawide-3440x1440.png" \
        "$sddm_theme/login-ultrawide-3440x1440.png"
    run sudo install -m 0644 "$ROOT/assets/wallpapers/login/login-16x10-3840x2400.png" \
        "$sddm_theme/login-16x10-3840x2400.png"

    backup_system_target /etc/sddm.conf.d/zz-artix-qylock.conf
    run sudo install -d -m 0755 /etc/sddm.conf.d
    run sudo install -m 0644 "$ROOT/system/sddm/zz-artix-qylock.conf" \
        /etc/sddm.conf.d/zz-artix-qylock.conf
    info 'SDDM was not restarted; the login theme takes effect at the next login.'

    if ((DRY_RUN)); then
        info "Backups would be stored below ${BACKUP_ROOT/#$HOME/~}"
    elif [[ -d $BACKUP_ROOT ]]; then
        info "System files backed up to ${BACKUP_ROOT/#$HOME/~}"
    fi
}

printf '%s%sBlade KDE setup%s\n' "$BOLD" "$BLUE" "$RESET"
((DRY_RUN)) && printf '%sDry run: no files, packages, or services will be changed.%s\n' "$YELLOW" "$RESET"

if ((DO_PACKAGES || DO_SYSTEM)); then
    begin_sudo_session
fi

((DO_PACKAGES)) && install_packages
((DO_USER)) && install_user_files
((DO_SYSTEM)) && configure_system

if ((DO_APPLY)); then
    section 'Applying the KDE session appearance'
    if ((DRY_RUN)); then
        run "$ROOT/scripts/apply-kde.sh" --dry-run
    else
        "$ROOT/scripts/apply-kde.sh"
    fi
fi

printf '\n%s✓ Blade KDE setup finished.%s\n' "$GREEN" "$RESET"
