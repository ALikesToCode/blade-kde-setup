#!/usr/bin/env bash

# Zen uses Blade-owned userChrome glyphs while its title bar is integrated.
# This bypasses GTK icon lookup, which can return chevrons despite Candy being
# the selected desktop icon theme.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ICONS="$ROOT/assets/icons/candy-icons/actions/scalable"
CHROME="$ROOT/dotfiles/apps/zen/chrome"

grep -Fq 'M4 10.5h8' "$ICONS/window-minimize-symbolic.svg" || {
    printf 'zen-window-controls: minimize must be a horizontal dash.\n' >&2
    exit 1
}
grep -Fq '<rect x="4.5" y="4.5" width="7" height="7"' \
    "$ICONS/window-maximize-symbolic.svg" || {
    printf 'zen-window-controls: maximize must be a window outline.\n' >&2
    exit 1
}
grep -Fq '<rect x="3.75" y="5.25" width="7" height="6"' \
    "$ICONS/window-restore-symbolic.svg" || {
    printf 'zen-window-controls: restore must use overlapping window outlines.\n' >&2
    exit 1
}
grep -Fq 'user_pref("browser.tabs.inTitlebar", 1);' \
    "$ROOT/dotfiles/apps/zen/user.js" || {
    printf 'zen-window-controls: Zen must retain its integrated, borderless title bar.\n' >&2
    exit 1
}
grep -Fq 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
    "$ROOT/dotfiles/apps/zen/user.js" || {
    printf 'zen-window-controls: userChrome loading must be enabled.\n' >&2
    exit 1
}
for control in minimize maximize restore close; do
    test -s "$CHROME/blade-window-$control.svg" || {
        printf 'zen-window-controls: missing Blade %s glyph.\n' "$control" >&2
        exit 1
    }
    grep -Fq "blade-window-$control.svg" "$CHROME/blade-window-controls.css" || {
        printf 'zen-window-controls: CSS does not bind the %s glyph.\n' "$control" >&2
        exit 1
    }
done
grep -Fq '.titlebar-min > .toolbarbutton-icon' "$CHROME/blade-window-controls.css"
grep -Fq '.titlebar-max > .toolbarbutton-icon' "$CHROME/blade-window-controls.css"
grep -Fq '.titlebar-restore > .toolbarbutton-icon' "$CHROME/blade-window-controls.css"
grep -Fq '.titlebar-close > .toolbarbutton-icon' "$CHROME/blade-window-controls.css"
if grep -Fq 'MOZ_GTK_TITLEBAR_DECORATION=system' "$ROOT/dotfiles/apps/zen/zen-browser"; then
    printf 'zen-window-controls: launcher still forces a separate system title bar.\n' >&2
    exit 1
fi

printf 'Zen integrated window-control check passed.\n'
