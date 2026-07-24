#!/usr/bin/env bash

# Load the real theme through Qt's QML engine without requiring a logout.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
THEME_DIR=${1:-$ROOT/kde/sddm/artix-material-you}

for icon in power session reboot sleep; do
    if [[ ! -s $THEME_DIR/icons/$icon.svg ]]; then
        printf 'sddm-theme: missing quick-settings icon: %s/icons/%s.svg\n' \
            "$THEME_DIR" "$icon" >&2
        exit 1
    fi
done

if command -v qmlscene6 >/dev/null 2>&1; then
    QMLSCENE=qmlscene6
elif command -v qmlscene >/dev/null 2>&1; then
    QMLSCENE=qmlscene
else
    printf 'sddm-theme: qmlscene is required for the runtime theme check.\n' >&2
    exit 77
fi

output_file=$(mktemp)
trap 'rm -f -- "$output_file"' EXIT

set +e
timeout 4s env \
    QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
    QML_IMPORT_PATH=/usr/lib/qt6/qml \
    "$QMLSCENE" "$THEME_DIR/Main.qml" >"$output_file" 2>&1
status=$?
set -e

if grep -Eq 'Cannot assign|QQmlApplicationEngine failed|Did not load any objects|is not a type|module .* is not installed' "$output_file"; then
    printf 'sddm-theme: QML engine rejected %s/Main.qml:\n' "$THEME_DIR" >&2
    cat "$output_file" >&2
    exit 1
fi

# A valid greeter remains open until the timeout; an immediate clean exit is
# also accepted for compatibility with alternate QML runners.
if [[ $status != 0 && $status != 124 ]]; then
    printf 'sddm-theme: QML engine exited unexpectedly with status %d:\n' "$status" >&2
    cat "$output_file" >&2
    exit 1
fi

printf 'SDDM theme runtime check passed.\n'
