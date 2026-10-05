#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
selector="$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-mode"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
unit_dir="$TEST_HOME/.config/systemd/user"
install -d -m 700 "$unit_dir" "$TEST_HOME/.config/codex-safe"
install -m 644 \
    "$ROOT/extras/hardened-workspace/payload/home/.config/systemd/user/playwright-safe-mcp.service" \
    "$unit_dir/playwright-safe-mcp.service"
mode_file="$TEST_HOME/.config/codex-safe/playwright-mcp-service-mode"

# Record the shared service state without touching the real user manager.
service_state="$TEST_ROOT/service-state"
fake_systemctl="$TEST_ROOT/systemctl"
cat >"$fake_systemctl" <<EOF
#!/usr/bin/env bash
[[ \$1 == --user ]] || exit 2
shift
state="$service_state"
case "\$1" in
    daemon-reload) ;;
    enable) printf 'enabled\\n' >>"\$state" ;;
    restart) printf 'active\\n' >>"\$state" ;;
    is-enabled) grep -Fqx enabled "\$state" 2>/dev/null ;;
    is-active) grep -Fqx active "\$state" 2>/dev/null ;;
    *) exit 2 ;;
esac
EOF
chmod 700 "$fake_systemctl"
export PLAYWRIGHT_MCP_SYSTEMCTL="$fake_systemctl"
config_dir="$TEST_HOME/.codex"
config_file="$config_dir/config.toml"
install -d -m 700 "$config_dir"
printf '%s\n' \
    'sentinel = "preserve-me"' \
    '' \
    '[mcp_servers.playwright_safe]' \
    "command = \"$TEST_HOME/.local/bin/playwright-mcp-cloak\"" \
    'args = ["--browser-mode=headless"]' \
    '' \
    '[mcp_servers.playwright_safe_headed]' \
    "command = \"$TEST_HOME/.local/bin/playwright-mcp-cloak\"" \
    'args = ["--browser-mode=headed"]' \
    >"$config_file"
chmod 600 "$config_file"

status=$(HOME="$TEST_HOME" python3 "$selector" status)
[[ "$status" == 'headless=enabled headed=enabled' ]]

result=$(HOME="$TEST_HOME" python3 "$selector" ensure)
[[ "$result" == headless=enabled\ headed=disabled\ restart-codex=yes\ backup=* ]]
[[ $(HOME="$TEST_HOME" python3 "$selector" status) == \
    'headless=enabled headed=disabled' ]]
grep -Fqx 'sentinel = "preserve-me"' "$config_file"
[[ $(grep -Fxc 'url = "http://localhost:49631/mcp"' "$config_file") -eq 2 ]]
! grep -Fq 'playwright-mcp-cloak' "$config_file"
[[ $(<"$mode_file") == headless && $(stat -Lc '%a' "$mode_file") == 600 ]]
grep -Fqx enabled "$service_state"
grep -Fqx active "$service_state"
[[ $(stat -Lc '%a' "$config_file") == 600 ]]
[[ $(find "$TEST_HOME/.local/state/codex-safe/config-backups" \
    -maxdepth 1 -type f | wc -l) -eq 1 ]]

result=$(HOME="$TEST_HOME" python3 "$selector" headed)
[[ "$result" == headless=disabled\ headed=enabled\ restart-codex=yes\ backup=* ]]
[[ $(<"$mode_file") == headed ]]
[[ $(HOME="$TEST_HOME" python3 "$selector" status) == \
    'headless=disabled headed=enabled' ]]
[[ $(find "$TEST_HOME/.local/state/codex-safe/config-backups" \
    -maxdepth 1 -type f | wc -l) -eq 2 ]]

result=$(HOME="$TEST_HOME" python3 "$selector" ensure)
[[ "$result" == 'headless=disabled headed=enabled restart-codex=no' ]]
[[ $(find "$TEST_HOME/.local/state/codex-safe/config-backups" \
    -maxdepth 1 -type f | wc -l) -eq 2 ]]

printf 'Browser mode selection tests passed.\n'
