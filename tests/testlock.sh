#!/usr/bin/env bash
# Exercise blade-testlock queueing, exit status, and slot release.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export XDG_RUNTIME_DIR=$TEST_ROOT BLADE_TEST_SLOTS=1
lock=$ROOT/bin/blade-testlock

status=0
"$lock" sh -c 'exit 7' || status=$?
[[ $status -eq 7 ]] || { printf 'exit status was not passed through\n' >&2; exit 1; }

"$lock" sleep 3 &
holder=$!
sleep 0.5
started=$(date +%s)
"$lock" true 2>"$TEST_ROOT/wait.log"
waited=$(($(date +%s) - started))
wait "$holder"
grep -Fq 'all 1 slots are busy; waiting' "$TEST_ROOT/wait.log"
((waited >= 2)) || { printf 'second run did not wait for the slot\n' >&2; exit 1; }

"$lock" sh -c 'sleep 5 & exit 0'
flock -n "$TEST_ROOT/blade-testlock/slot-1" true || {
    printf 'a background child kept the slot\n' >&2
    exit 1
}

status=0
BLADE_TEST_SLOTS=0 "$lock" true 2>/dev/null || status=$?
[[ $status -eq 2 ]]
printf 'Test slot queueing checks passed.\n'
