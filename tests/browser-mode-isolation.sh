#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-cloak"
runtime="$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/runtime-inner.sh"
nested="$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/nested-display.sh"
safe_mcp="$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-safe"
safe_cli="$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-cli"
installer="$ROOT/extras/hardened-workspace/install.sh"

headless=$(bash "$launcher" --browser-mode=headless --describe-browser-mode)
[[ "$headless" == 'browser-mode=headless display=disabled input=cdp-only' ]]

headed=$(bash "$launcher" --browser-mode=headed --describe-browser-mode)
[[ "$headed" == 'browser-mode=headed display=visible-nested-kde input=cdp-only' ]]

if bash "$launcher" --describe-browser-mode >/dev/null 2>&1; then
    printf 'Launcher accepted an implicit browser mode\n' >&2
    exit 1
fi

if bash "$launcher" --browser-mode=headless --browser-mode=headed \
    --describe-browser-mode >/dev/null 2>&1; then
    printf 'Launcher accepted conflicting browser modes\n' >&2
    exit 1
fi

grep -Fq 'setsid env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY' "$launcher"
grep -Fq 'runtime_root="/tmp/playwright-mcp-cloak-$(id -u)"' "$launcher"
grep -Fq 'codex_safe_start_nested_display "$runtime_root"' "$launcher"
grep -Fq 'headed cloakserve connected directly to the host KDE display' "$launcher"
grep -Fq '"--password-store=basic"' "$launcher"
grep -Fq 'DBUS_SESSION_BUS_ADDRESS=disabled:' "$launcher"
grep -Fq -- '-name cloakbrowser-automation' "$nested"
grep -Fq -- "-title 'CloakBrowser Automation (CDP only)'" "$nested"
grep -Fq 'XAUTHORITY="$CODEX_SAFE_NESTED_XAUTHORITY"' "$nested"
grep -Fq 'CODEX_SAFE_NESTED_COOKIE' "$runtime"
grep -Fq '"--password-store=basic"' "$runtime"
if grep -Fq 'xvfb' "$launcher" "$runtime" "$nested"; then
    printf 'Visible headed mode still depends on off-screen Xvfb\n' >&2
    exit 1
fi
grep -Fq 'mcp_servers.playwright_safe.args=[]' "$runtime"
grep -Fq 'shell_environment_policy.set.CODEX_SAFE_BROWSER_MODE' "$runtime"
grep -Fq 'exec env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY' "$safe_mcp"
grep -Fq 'unset DISPLAY WAYLAND_DISPLAY XAUTHORITY' "$safe_cli"
grep -Fq -- '--key acceptfocus --type bool false' "$installer"
grep -Fq -- '--key acceptfocusrule 2' "$installer"

printf 'Browser mode isolation tests passed.\n'
