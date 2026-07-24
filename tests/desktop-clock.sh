#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WIDGET="$ROOT/kde/plasma/plasmoids/org.mysterious.bladeclock"

python3 -m json.tool "$WIDGET/metadata.json" >/dev/null
grep -Fq '"X-Plasma-API-Minimum-Version": "6.0"' "$WIDGET/metadata.json"
grep -Fq 'Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground' \
    "$WIDGET/contents/ui/main.qml"
grep -Fq 'color hourColor: "#AECBFA"' "$WIDGET/contents/ui/main.qml"
grep -Fq 'color minuteColor: "#81C995"' "$WIDGET/contents/ui/main.qml"
grep -Fq 'desktop.addWidget(bladeClockType, x, y, width, height);' \
    "$ROOT/kde/plasma/blade-desktop-clock.js"

if command -v qmllint >/dev/null 2>&1; then
    qmllint -I /usr/lib/qt6/qml "$WIDGET/contents/ui/main.qml"
elif command -v qmllint6 >/dev/null 2>&1; then
    qmllint6 -I /usr/lib/qt6/qml "$WIDGET/contents/ui/main.qml"
else
    printf 'desktop-clock: qmllint is required.\n' >&2
    exit 77
fi

printf 'Blade desktop clock check passed.\n'
