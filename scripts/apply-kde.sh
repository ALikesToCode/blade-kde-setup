#!/usr/bin/env bash

set -Eeuo pipefail

DRY_RUN=0
[[ ${1:-} == --dry-run ]] && DRY_RUN=1

run() {
    if ((DRY_RUN)); then
        local arg
        printf '  $'
        for arg in "$@"; do printf ' %q' "$arg"; done
        printf '\n'
    else
        "$@"
    fi
}

warn() { printf '  ! %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

if ! have kwriteconfig6; then
    if ((DRY_RUN)); then
        warn 'kwriteconfig6 is not installed on this machine; continuing the dry-run.'
    else
        printf 'apply-kde: kwriteconfig6 is required (install plasma-workspace).\n' >&2
        exit 1
    fi
fi

printf 'Applying Artix Dark Rounded with blue accents...\n'

if have plasma-apply-lookandfeel; then
    run plasma-apply-lookandfeel --apply org.mysterious.artixdarkrounded.desktop
else
    warn 'plasma-apply-lookandfeel was not found; applying the same settings individually.'
fi

run kwriteconfig6 --file kdeglobals --group General --key ColorScheme ArtixDarkRounded
run kwriteconfig6 --file kdeglobals --group Icons --key Theme candy-icons
run kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze
run kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme breeze_cursors
# Use Plasma's complete, version-matched surface assets. The Artix color scheme
# still provides the blue/green application accents.
run kwriteconfig6 --file plasmarc --group Theme --key name breeze-dark

run kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.klassy
run kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Klassy
run kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft M
run kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight IAX

# Keep Konsole native and clickable. The optional QSS is installed for reference,
# but a process-wide stylesheet previously captured mouse input and broke tabs.
run kwriteconfig6 --file konsolerc --group Desktop Entry --key DefaultProfile 'Artix Dark Rounded.profile'
run kwriteconfig6 --file konsolerc --group TabBar --key CloseTabButton 0
run kwriteconfig6 --file konsolerc --group TabBar --key ExpandTabWidth false
run kwriteconfig6 --file konsolerc --group TabBar --key TabBarUseUserStyleSheet false
run kwriteconfig6 --file konsolerc --group TabBar --key TabBarUserStyleSheetFile \
    "$HOME/.local/share/konsole/ArtixDarkRoundedTabs.qss"

if have klassy-settings; then
    if ((DRY_RUN)); then
        run klassy-settings --import-preset "$HOME/.local/share/klassy/Artix_Dark_Rounded.klpw"
        run klassy-settings --load-windeco-preset 'Artix Dark Rounded'
        run klassy-settings --generate-system-icons
    else
        if ! klassy-settings --import-preset "$HOME/.local/share/klassy/Artix_Dark_Rounded.klpw"; then
            warn 'Klassy did not import the preset (it may already exist or target another Klassy version).'
        fi
        if ! klassy-settings --load-windeco-preset 'Artix Dark Rounded'; then
            warn 'Klassy could not activate the Artix Dark Rounded preset.'
        fi
        klassy-settings --generate-system-icons || warn 'Klassy system-icon generation failed.'
    fi
else
    warn 'Klassy is not installed; Breeze remains available until the AUR package is installed.'
fi

if ((DRY_RUN)); then
    run "$(dirname -- "${BASH_SOURCE[0]}")/apply-wallpapers.sh" --dry-run
else
    "$(dirname -- "${BASH_SOURCE[0]}")/apply-wallpapers.sh"
fi

if have kbuildsycoca6; then
    run kbuildsycoca6
fi

QDBUS=
if have qdbus6; then QDBUS=qdbus6; elif have qdbus; then QDBUS=qdbus; fi
if [[ -n $QDBUS ]]; then
    if ((DRY_RUN)); then
        run "$QDBUS" org.kde.KWin /KWin org.kde.KWin.reconfigure
    else
        "$QDBUS" org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 \
            || warn 'KWin is not running; its decoration will apply next session.'
    fi
fi

printf 'Artix Dark Rounded is configured. Restart Konsole to load its profile.\n'
