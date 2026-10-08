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
            printf 'Install Blade Music; --activate configures myMPD and starts MPD, myMPD, and the sync timer.\n'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
    esac
done

DATA_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG_ROOT=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_ROOT=${XDG_STATE_HOME:-$HOME/.local/state}
CACHE_ROOT=${XDG_CACHE_HOME:-$HOME/.cache}
BACKUP_ROOT=${BLADE_BACKUP_ROOT:-$STATE_ROOT/blade-kde-backups/music-$(date +%Y%m%d-%H%M%S-%N)}
RENDER_DIR=$(mktemp -d)
trap 'rm -rf -- "$RENDER_DIR"' EXIT

copy_file() {
    local source=$1 target=$2 mode=${3:-644}
    if [[ -f $target ]] && cmp -s -- "$source" "$target"; then
        return
    fi
    if ((DRY_RUN)); then
        printf 'Would install %s -> %s\n' "${source#"$RENDER_DIR"/}" "$target"
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

# myMPD reads each setting from its own file, without a trailing newline.
write_value() {
    local target=$1 value=$2 rendered
    rendered="$RENDER_DIR/$(basename -- "$target")"
    printf '%s' "$value" >"$rendered"
    copy_file "$rendered" "$target"
}

copy_file "$ROOT/bin/blade-music" "$HOME/.local/bin/blade-music" 755
copy_file "$ROOT/bin/blade-music-web" "$HOME/.local/bin/blade-music-web" 755
for source in "$ROOT"/lib/blade_music/*.py; do
    copy_file "$source" "$DATA_ROOT/blade-kde/lib/blade_music/${source##*/}"
done
for unit in blade-music-sync.service blade-music-sync-now.service blade-music-sync.timer; do
    copy_file "$ROOT/dotfiles/systemd/user/$unit" "$CONFIG_ROOT/systemd/user/$unit"
done
if [[ ! -e $CONFIG_ROOT/blade-music.toml ]]; then
    copy_file "$ROOT/dotfiles/music/blade-music.toml" "$CONFIG_ROOT/blade-music.toml" 600
fi
copy_file "$ROOT/dotfiles/music/mpd.conf" "$CONFIG_ROOT/mpd/mpd.conf"
copy_file "$ROOT/dotfiles/music/mympd/Sync YouTube Music.lua" \
    "$CONFIG_ROOT/mympd/scripts/Sync YouTube Music.lua"
plasmoid=org.mysterious.blademusic
copy_file "$ROOT/kde/plasma/plasmoids/$plasmoid/metadata.json" "$DATA_ROOT/plasma/plasmoids/$plasmoid/metadata.json"
copy_file "$ROOT/kde/plasma/plasmoids/$plasmoid/contents/ui/main.qml" "$DATA_ROOT/plasma/plasmoids/$plasmoid/contents/ui/main.qml"
copy_file "$ROOT/kde/plasma/music-controls.js" "$DATA_ROOT/blade-kde/music-controls.js"
sed "s|__HOME__|$HOME|g" "$ROOT/dotfiles/apps/blade-music/blade-music.desktop" >"$RENDER_DIR/blade-music.desktop"
copy_file "$RENDER_DIR/blade-music.desktop" "$DATA_ROOT/applications/blade-music.desktop"

((ACTIVATE)) || exit 0
if ((DRY_RUN)); then
    printf 'Would configure myMPD for loopback-only access, start mpd, mpd-mpris, mympd, and blade-music-sync.timer,\n'
    printf 'and add Blade Music to existing application panels.\n'
    exit 0
fi
for executable in python3 mpd mpc mympd mpd-mpris yt-dlp ffmpeg systemctl qdbus6; do
    command -v "$executable" >/dev/null || {
        printf 'Missing %s. Install prerequisites: sudo pacman -S --needed mpd mpc mpd-mpris mympd rmpc python-ytmusicapi python-mutagen yt-dlp yt-dlp-ejs ffmpeg\n' "$executable" >&2
        exit 1
    }
done
python3 -c 'import mutagen, yt_dlp, ytmusicapi' 2>/dev/null || {
    printf 'Missing Python modules. Install: sudo pacman -S --needed python-ytmusicapi python-mutagen yt-dlp\n' >&2
    exit 1
}
mkdir -p -- "$STATE_ROOT/mpd" "$DATA_ROOT/mpd/playlists"

mympd_config="$CONFIG_ROOT/mympd"
if [[ ! -d $mympd_config/config ]]; then
    MYMPD_HTTP_HOST=127.0.0.1 MYMPD_SSL=false MYMPD_ACL=+127.0.0.0/8 \
        mympd -c -w "$mympd_config" -a "$CACHE_ROOT/mympd" >/dev/null
fi
# Loopback only: the laptop joins public Wi-Fi, and myMPD otherwise accepts any host.
write_value "$mympd_config/config/http_host" 127.0.0.1
write_value "$mympd_config/config/ssl" false
write_value "$mympd_config/config/acl" +127.0.0.0/8
# MPD shares its music directory only over the socket, which enables covers and the library view.
write_value "$mympd_config/state/mpd_host" "$STATE_ROOT/mpd/socket"

systemctl --user daemon-reload
systemctl --user enable --now mpd.service mpd-mpris.service mympd.service blade-music-sync.timer
systemctl --user restart mympd.service
layout="$CONFIG_ROOT/plasma-org.kde.plasma.desktop-appletsrc"
if [[ -f $layout ]]; then
    mkdir -p -- "$BACKUP_ROOT"
    cp -a -- "$layout" "$BACKUP_ROOT/plasma-org.kde.plasma.desktop-appletsrc"
    printf 'Panel backup: %s/plasma-org.kde.plasma.desktop-appletsrc\n' "$BACKUP_ROOT"
fi
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    "$(<"$DATA_ROOT/blade-kde/music-controls.js")"
if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$DATA_ROOT/applications"
fi
printf 'Blade Music is active. Open it with blade-music-web; sync now with blade-music sync-now.\n'
