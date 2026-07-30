#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
profile_lib="$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/browser-profile.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/blade-browser-profile.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

test_home="$test_root/home"
mkdir -m 700 "$test_home"
export HOME=$test_home
export CODEX_SAFE_HOST_HOME=$test_home
export CODEX_SAFE_BROWSER_PROFILE_ROOT="$test_home/.local/state/codex-safe/cloakbrowser-profile"

# shellcheck source=/dev/null
source "$profile_lib"

codex_safe_browser_profile_acquire
first_seed=$CODEX_SAFE_FINGERPRINT_SEED
printf 'retained\n' >"$CODEX_SAFE_BROWSER_STATE/persistence-marker"
codex_safe_browser_profile_release

codex_safe_browser_profile_acquire
second_seed=$CODEX_SAFE_FINGERPRINT_SEED
[[ "$first_seed" == "$second_seed" ]]
[[ -f "$CODEX_SAFE_BROWSER_STATE/persistence-marker" ]]
[[ $(stat -Lc '%a' -- "$CODEX_SAFE_BROWSER_PROFILE_ROOT") == 700 ]]
[[ $(stat -Lc '%a' -- "$CODEX_SAFE_BROWSER_STATE") == 700 ]]
[[ $(stat -Lc '%a' -- "$CODEX_SAFE_BROWSER_PROFILE_ROOT/fingerprint-seed") == 600 ]]

if HOME="$test_home" \
    CODEX_SAFE_HOST_HOME="$test_home" \
    CODEX_SAFE_BROWSER_PROFILE_ROOT="$CODEX_SAFE_BROWSER_PROFILE_ROOT" \
    bash -c 'source "$1"; codex_safe_browser_profile_acquire' _ "$profile_lib" \
    >/dev/null 2>&1; then
    printf 'Concurrent browser profile acquisition unexpectedly succeeded\n' >&2
    exit 1
fi
codex_safe_browser_profile_release

unsafe_home="$test_root/unsafe-home"
install -d -m 700 "$unsafe_home/.local/state/codex-safe" "$test_root/symlink-target"
ln -s "$test_root/symlink-target" \
    "$unsafe_home/.local/state/codex-safe/cloakbrowser-profile"
if HOME="$unsafe_home" \
    CODEX_SAFE_HOST_HOME="$unsafe_home" \
    CODEX_SAFE_BROWSER_PROFILE_ROOT="$unsafe_home/.local/state/codex-safe/cloakbrowser-profile" \
    bash -c 'source "$1"; codex_safe_browser_profile_acquire' _ "$profile_lib" \
    >/dev/null 2>&1; then
    printf 'Symlinked browser profile unexpectedly succeeded\n' >&2
    exit 1
fi

printf 'Browser profile persistence tests passed.\n'
