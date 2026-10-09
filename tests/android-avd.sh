#!/usr/bin/env bash
# Exercise AVD tuning: GPU on, only-raise cores and RAM, idempotence, backup.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export ANDROID_AVD_HOME=$TEST_ROOT/avd BLADE_BACKUP_ROOT=$TEST_ROOT/backup
mkdir -p "$ANDROID_AVD_HOME/small.avd" "$ANDROID_AVD_HOME/large.avd"
printf 'hw.cpu.ncore = 4\nhw.gpu.enabled = no\nhw.gpu.mode = auto\nhw.ramSize = 2G\n' \
    >"$ANDROID_AVD_HOME/small.avd/config.ini"
printf 'hw.cpu.ncore = 12\nhw.ramSize = 8192\n' >"$ANDROID_AVD_HOME/large.avd/config.ini"
cp "$ANDROID_AVD_HOME/small.avd/config.ini" "$TEST_ROOT/original.ini"

"$ROOT/scripts/tune-android-avd.sh" --dry-run >/dev/null
cmp -s "$ANDROID_AVD_HOME/small.avd/config.ini" "$TEST_ROOT/original.ini"

"$ROOT/scripts/tune-android-avd.sh" >/dev/null
small=$ANDROID_AVD_HOME/small.avd/config.ini large=$ANDROID_AVD_HOME/large.avd/config.ini
grep -Fqx 'hw.gpu.enabled = yes' "$small"
grep -Fqx 'hw.gpu.mode = host' "$small"
grep -Fqx 'hw.cpu.ncore = 8' "$small"
grep -Fqx 'hw.ramSize = 4096M' "$small"
grep -Fqx 'hw.cpu.ncore = 12' "$large"
grep -Fqx 'hw.ramSize = 8192' "$large"
grep -Fqx 'hw.gpu.mode = host' "$large"
cmp -s "$BLADE_BACKUP_ROOT/small.avd/config.ini" "$TEST_ROOT/original.ini"
"$ROOT/scripts/tune-android-avd.sh" small | grep -Fq 'small is already tuned.'
printf 'Android AVD tuning checks passed.\n'
