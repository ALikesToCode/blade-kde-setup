#!/usr/bin/env bash

set -Eeuo pipefail

DRY_RUN=0
[[ ${1:-} == --dry-run ]] && DRY_RUN=1

standard="$HOME/.local/share/wallpapers/BladeKDE/desktop/desktop-16x10-3840x2400.png"
ultrawide="$HOME/.local/share/wallpapers/BladeKDE/desktop/desktop-ultrawide-3440x1440.png"

if ((DRY_RUN)); then
    printf '  set 16:10 wallpaper: %s\n' "$standard"
    printf '  set ultrawide wallpaper: %s\n' "$ultrawide"
    exit 0
fi

[[ -f $standard && -f $ultrawide ]] || {
    printf 'apply-wallpapers: install the Blade KDE wallpaper assets first.\n' >&2
    exit 1
}

if command -v qdbus6 >/dev/null 2>&1; then
    QDBUS=qdbus6
elif command -v qdbus >/dev/null 2>&1; then
    QDBUS=qdbus
else
    printf 'apply-wallpapers: qdbus6 was not found; wallpapers were installed but not applied.\n' >&2
    exit 0
fi

escape_js() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

standard_js=$(escape_js "$standard")
ultrawide_js=$(escape_js "$ultrawide")

read -r -d '' script <<EOF || true
var views = desktops();
for (var i = 0; i < views.length; ++i) {
    var desktop = views[i];
    var wide = false;
    try {
        var geometry = screenGeometry(desktop.screen);
        wide = geometry.height > 0 && (geometry.width / geometry.height) > 2.0;
    } catch (error) {
        // Stable fallback for the Blade dual-display layout: standard first,
        // ultrawide second. KDE geometry detection is used whenever available.
        wide = i > 0;
    }
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", "file://" + (wide ? "$ultrawide_js" : "$standard_js"));
    desktop.writeConfig("FillMode", 2);
}
EOF

if ! "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script" >/dev/null; then
    printf 'apply-wallpapers: Plasma is not running; wallpapers will remain available in System Settings.\n' >&2
fi
