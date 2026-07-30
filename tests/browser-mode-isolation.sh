#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

launcher="$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-cloak"
runtime="$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/runtime-inner.sh"
nested="$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/nested-display.sh"
window_manager="$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/nested-window-manager.py"
safe_mcp="$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-safe"
safe_cli="$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-cli"
installer="$ROOT/extras/hardened-workspace/install.sh"

headless=$(bash "$launcher" --browser-mode=headless --describe-browser-mode)
[[ "$headless" == 'browser-mode=headless display=disabled profile=persistent input=cdp-only' ]]

headed=$(bash "$launcher" --browser-mode=headed --describe-browser-mode)
[[ "$headed" == 'browser-mode=headed display=visible-nested-kde profile=persistent input=host-and-cdp' ]]

TEST_HOME="$TEST_ROOT/home"
install -d -m 700 "$TEST_HOME"
home_artifact_root=$(
    cd "$TEST_HOME"
    HOME="$TEST_HOME" bash "$launcher" \
        --browser-mode=headless --describe-artifact-root
)
[[ "$home_artifact_root" == \
    "$TEST_HOME/.local/state/codex-safe/playwright-mcp-workspace/.playwright-cli" ]]
[[ $(stat -Lc '%a' "$TEST_HOME/.local/state/codex-safe") == 700 ]]
[[ $(stat -Lc '%a' \
    "$TEST_HOME/.local/state/codex-safe/playwright-mcp-workspace") == 700 ]]

project_workspace="$TEST_HOME/project"
install -d -m 700 "$project_workspace"
project_artifact_root=$(
    cd "$project_workspace"
    HOME="$TEST_HOME" bash "$launcher" \
        --browser-mode=headless --describe-artifact-root
)
[[ "$project_artifact_root" == "$project_workspace/.playwright-cli" ]]

if (
    cd /
    HOME="$TEST_HOME" bash "$launcher" \
        --browser-mode=headless --describe-artifact-root
) >/dev/null 2>&1; then
    printf 'Launcher accepted the filesystem root as an artifact workspace\n' >&2
    exit 1
fi

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
# shellcheck disable=SC2016
grep -Fq 'runtime_root="/tmp/playwright-mcp-cloak-$(id -u)"' "$launcher"
# shellcheck disable=SC2016
grep -Fq 'codex_safe_start_nested_display "$runtime_root"' "$launcher"
grep -Fq 'headed cloakserve connected directly to the host KDE display' "$launcher"
grep -Fq '"--password-store=basic"' "$launcher"
grep -Fq 'DBUS_SESSION_BUS_ADDRESS=disabled:' "$launcher"
grep -Fq 'codex_safe_browser_profile_acquire' "$launcher"
grep -Fq 'isolated:false' "$launcher"
if grep -Fq 'saveSession:true' "$launcher"; then
    printf 'Persistent profile also exports authentication state into the workspace\n' >&2
    exit 1
fi
grep -Fq -- '-name cloakbrowser-automation' "$nested"
grep -Fq -- "-title 'CloakBrowser Automation'" "$nested"
# shellcheck disable=SC2016
grep -Fq 'XAUTHORITY="$CODEX_SAFE_NESTED_XAUTHORITY"' "$nested"
# shellcheck disable=SC2016
grep -Fq 'codex_safe_start_clipboard_bridge "$state_root"' "$nested"
# shellcheck disable=SC2016
grep -Fq 'codex_safe_start_nested_window_manager "$state_root"' "$nested"
grep -Fq 'SUBSTRUCTURE_REDIRECT_MASK' "$window_manager"
grep -Fq 'event.type == CONFIGURE_REQUEST' "$window_manager"
grep -Fq 'self.lib.XMoveResizeWindow(self.display, window, 0, 0, width, height)' \
    "$window_manager"
grep -Fq 'self.lib.XSetInputFocus(' "$window_manager"
if grep -Eq 'xdotool|ydotool|wtype' "$window_manager"; then
    printf 'Nested window handling uses forbidden host input tooling\n' >&2
    exit 1
fi
grep -Fq 'CODEX_SAFE_NESTED_COOKIE' "$runtime"
grep -Fq '"--password-store=basic"' "$runtime"
grep -Fq 'codex_safe_browser_profile_load' "$runtime"
if grep -Fq 'xvfb' "$launcher" "$runtime" "$nested"; then
    printf 'Visible headed mode still depends on off-screen Xvfb\n' >&2
    exit 1
fi
grep -Fq 'mcp_servers.playwright_safe.args=[]' "$runtime"
grep -Fq 'shell_environment_policy.set.CODEX_SAFE_BROWSER_MODE' "$runtime"
grep -Fq 'exec env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY' "$safe_mcp"
grep -Fq 'unset DISPLAY WAYLAND_DISPLAY XAUTHORITY' "$safe_cli"
grep -Fq -- '--key acceptfocus --type bool true' "$installer"
grep -Fq -- '--key acceptfocusrule 2' "$installer"
grep -Fq -- '--key fsplevel 0' "$installer"

printf 'Browser mode isolation tests passed.\n'
