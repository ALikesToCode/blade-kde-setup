#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

script="$ROOT/scripts/configure-codex-desktop.sh"
desired='enabled-reasoning-efforts = ["low", "medium", "high", "xhigh", "max", "ultra"]'

existing_home="$TEST_ROOT/existing-home"
existing_config="$existing_home/.codex/config.toml"
existing_backup="$TEST_ROOT/existing-backup"
install -d -m 700 -- "$(dirname -- "$existing_config")"
chmod 750 -- "$(dirname -- "$existing_config")"
printf '%s\n' \
    'model = "gpt-5.6-sol"' \
    'sentinel = "preserve-me"' \
    '' \
    '[desktop]' \
    'conversationDetailMode = "STEPS_COMMANDS"' \
    'enabled-reasoning-efforts = [' \
    '  "low",' \
    '  "ultra",' \
    ']' \
    '' \
    '[features]' \
    'memories = true' \
    >"$existing_config"
chmod 600 -- "$existing_config"
cp -- "$existing_config" "$TEST_ROOT/original-config.toml"

HOME="$existing_home" BLADE_BACKUP_ROOT="$existing_backup" "$script" >/dev/null
grep -Fqx "$desired" "$existing_config"
grep -Fqx 'sentinel = "preserve-me"' "$existing_config"
grep -Fqx 'conversationDetailMode = "STEPS_COMMANDS"' "$existing_config"
grep -Fqx '[features]' "$existing_config"
grep -Fqx 'memories = true' "$existing_config"
[[ $(grep -Fxc "$desired" "$existing_config") -eq 1 ]]
[[ $(stat -Lc '%a' -- "$existing_config") == 600 ]]
[[ $(stat -Lc '%a' -- "$(dirname -- "$existing_config")") == 750 ]]
backup_file="$existing_backup/${existing_config#/}"
cmp -s -- "$TEST_ROOT/original-config.toml" "$backup_file"

before_hash=$(sha256sum "$existing_config")
HOME="$existing_home" BLADE_BACKUP_ROOT="$existing_backup" "$script" >/dev/null
[[ $(sha256sum "$existing_config") == "$before_hash" ]]
[[ $(find "$existing_backup" -type f | wc -l) -eq 1 ]]

new_home="$TEST_ROOT/new-home"
new_config="$new_home/.codex/config.toml"
HOME="$new_home" BLADE_BACKUP_ROOT="$TEST_ROOT/new-backup" "$script" >/dev/null
grep -Fqx '[desktop]' "$new_config"
grep -Fqx "$desired" "$new_config"
[[ $(stat -Lc '%a' -- "$new_config") == 600 ]]
[[ $(stat -Lc '%a' -- "$(dirname -- "$new_config")") == 700 ]]
[[ ! -e $TEST_ROOT/new-backup ]]

dry_home="$TEST_ROOT/dry-home"
dry_config="$dry_home/.codex/config.toml"
install -d -m 700 -- "$(dirname -- "$dry_config")"
printf 'sentinel = "dry-run"\n' >"$dry_config"
cp -- "$dry_config" "$TEST_ROOT/dry-original.toml"
HOME="$dry_home" BLADE_BACKUP_ROOT="$TEST_ROOT/dry-backup" \
    "$script" --dry-run >/dev/null
cmp -s -- "$TEST_ROOT/dry-original.toml" "$dry_config"
[[ ! -e $TEST_ROOT/dry-backup ]]

unsafe_home="$TEST_ROOT/unsafe-home"
install -d -m 700 -- "$unsafe_home/.codex"
ln -s "$TEST_ROOT/original-config.toml" "$unsafe_home/.codex/config.toml"
if HOME="$unsafe_home" "$script" >/dev/null 2>&1; then
    printf 'Codex Desktop configuration must refuse a symlink target.\n' >&2
    exit 1
fi

printf 'Codex Desktop configuration tests passed.\n'
