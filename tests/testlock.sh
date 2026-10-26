#!/usr/bin/env bash
# Exercise blade-testlock queueing, the quick lane, holder reports, exit
# status, and slot release.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export XDG_RUNTIME_DIR=$TEST_ROOT BLADE_TEST_SLOTS=1 BLADE_TEST_QUICK_SLOTS=1
lock=$ROOT/bin/blade-testlock
fail() { printf '%s\n' "$1" >&2; exit 1; }

status=0
"$lock" sh -c 'exit 7' || status=$?
[[ $status -eq 7 ]] || fail 'exit status was not passed through'

"$lock" sleep 3 &
holder=$!
sleep 0.5
started=$(date +%s)
"$lock" true 2>"$TEST_ROOT/wait.log"
waited=$(($(date +%s) - started))
grep -Fq 'all 1 slots are busy; waiting' "$TEST_ROOT/wait.log"
grep -Eq '^  slot 1 +[0-9]+s  sleep 3  \(' "$TEST_ROOT/wait.log" ||
    fail 'the wait message did not name the holder'
((waited >= 2)) || fail 'second run did not wait for the slot'
wait "$holder"

# A quick job runs at once while a long job holds every full slot.
"$lock" sleep 3 &
holder=$!
sleep 0.5
"$lock" --status >"$TEST_ROOT/status.log"
grep -Eq '^  slot 1 +[0-9]+s  sleep 3  \(' "$TEST_ROOT/status.log" ||
    fail '--status did not show the holder'
grep -Eq '^  quick 1 +free$' "$TEST_ROOT/status.log" || fail '--status did not show a free slot'
started=$(date +%s)
"$lock" --quick true 2>"$TEST_ROOT/quick.log"
(($(date +%s) - started < 2)) || fail 'a quick job waited behind a full one'
[[ ! -s $TEST_ROOT/quick.log ]] || fail 'a quick job reported waiting'
wait "$holder"

# A full job never takes a quick slot.
"$lock" --quick sleep 3 &
holder=$!
sleep 0.5
"$lock" sleep 3 &
second=$!
sleep 0.5
started=$(date +%s)
"$lock" true 2>"$TEST_ROOT/full.log"
(($(date +%s) - started >= 2)) || fail 'a full job took a quick slot'
grep -Fq 'all 1 slots are busy; waiting' "$TEST_ROOT/full.log"
wait "$holder" "$second"

# A quick job falls back to a free full slot when the quick slots are taken.
"$lock" --quick sleep 3 &
holder=$!
sleep 0.5
started=$(date +%s)
"$lock" --quick true 2>/dev/null
(($(date +%s) - started < 2)) || fail 'a quick job did not use the free full slot'
wait "$holder"

[[ -z $(find "$TEST_ROOT/blade-testlock" -name '*.holder*') ]] ||
    fail 'a finished job left its holder record'

"$lock" sh -c 'sleep 5 & exit 0'
flock -n "$TEST_ROOT/blade-testlock/slot-1" true || fail 'a background child kept the slot'

status=0
BLADE_TEST_SLOTS=0 "$lock" true 2>/dev/null || status=$?
[[ $status -eq 2 ]]
status=0
BLADE_TEST_QUICK_SLOTS=x "$lock" --quick true 2>/dev/null || status=$?
[[ $status -eq 2 ]]
status=0
"$lock" --quick >/dev/null || status=$?
[[ $status -eq 2 ]]
printf 'Test slot queueing checks passed.\n'
