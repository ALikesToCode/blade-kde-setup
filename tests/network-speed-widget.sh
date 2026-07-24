#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PANEL_SCRIPT="$ROOT/kde/plasma/blade-panels.js"

[[ $(grep -Fc '    bladeNetworkMonitor,' "$PANEL_SCRIPT") -eq 2 ]]
grep -Fq 'var sensors = ["network/all/download", "network/all/upload"];' "$PANEL_SCRIPT"
grep -Fq '"chartFace": "org.kde.ksysguard.textonly"' "$PANEL_SCRIPT"
grep -Fq '"network/all/download": "DOWN"' "$PANEL_SCRIPT"
grep -Fq '"network/all/upload": "UP"' "$PANEL_SCRIPT"
grep -Fq 'bladePlaceWidgetAfter(panel, networkWidgets[0], "org.kde.plasma.systemmonitor");' \
    "$PANEL_SCRIPT"
grep -Fq 'var BLADE_POSITION_ONLY = false;' "$ROOT/scripts/apply-panels.sh"
grep -Fq 'var BLADE_POSITION_ONLY = true;' "$ROOT/scripts/apply-panels.sh"

plan=$("$ROOT/scripts/apply-panels.sh" --dry-run)
grep -Fq 'live download/upload speed' <<<"$plan"

printf 'Network-speed widget checks passed.\n'
