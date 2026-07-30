#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
selector="$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-mode"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
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
[[ $(stat -Lc '%a' "$config_file") == 600 ]]
[[ $(find "$TEST_HOME/.local/state/codex-safe/config-backups" \
    -maxdepth 1 -type f | wc -l) -eq 1 ]]

result=$(HOME="$TEST_HOME" python3 "$selector" headed)
[[ "$result" == headless=disabled\ headed=enabled\ restart-codex=yes\ backup=* ]]
[[ $(HOME="$TEST_HOME" python3 "$selector" status) == \
    'headless=disabled headed=enabled' ]]
[[ $(find "$TEST_HOME/.local/state/codex-safe/config-backups" \
    -maxdepth 1 -type f | wc -l) -eq 2 ]]

result=$(HOME="$TEST_HOME" python3 "$selector" ensure)
[[ "$result" == 'headless=disabled headed=enabled restart-codex=no' ]]
[[ $(find "$TEST_HOME/.local/state/codex-safe/config-backups" \
    -maxdepth 1 -type f | wc -l) -eq 2 ]]

printf 'Browser mode selection tests passed.\n'
