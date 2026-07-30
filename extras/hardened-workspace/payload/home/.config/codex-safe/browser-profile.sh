#!/usr/bin/env bash
# Owns the single persistent CloakBrowser profile and its stable fingerprint.

codex_safe_browser_profile_error() {
  printf 'browser-profile: ERROR: %s\n' "$*" >&2
  return 1
}

codex_safe_stop_cloakserve() {
  local pid=$1
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0

  # Signal only cloakserve first. Its aiohttp shutdown hook asks Chromium to
  # close through CDP and waits so the profile can flush cookies and storage.
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    for _ in {1..100}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
  fi

  # A stuck server or orphaned browser must not escape the owning launcher.
  if kill -0 -- "-$pid" 2>/dev/null; then
    kill -TERM -- "-$pid" 2>/dev/null || true
    for _ in {1..30}; do
      kill -0 -- "-$pid" 2>/dev/null || break
      sleep 0.1
    done
  fi
  if kill -0 -- "-$pid" 2>/dev/null; then
    kill -KILL -- "-$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

codex_safe_browser_profile_check_dir() {
  local path=$1 label=$2 owner mode
  [[ -d "$path" && ! -L "$path" ]] || \
    codex_safe_browser_profile_error "$label is missing or is a symlink" || return
  owner=$(stat -Lc '%u' -- "$path" 2>/dev/null) || return
  mode=$(stat -Lc '%a' -- "$path" 2>/dev/null) || return
  [[ "$owner" == "$(id -u)" ]] || \
    codex_safe_browser_profile_error "$label has the wrong owner" || return
  (( (8#$mode & 8#077) == 0 )) || \
    codex_safe_browser_profile_error "$label is accessible by group or world" || return
}

codex_safe_browser_profile_check_file() {
  local path=$1 label=$2 owner mode
  [[ -f "$path" && ! -L "$path" ]] || \
    codex_safe_browser_profile_error "$label is missing or is a symlink" || return
  owner=$(stat -Lc '%u' -- "$path" 2>/dev/null) || return
  mode=$(stat -Lc '%a' -- "$path" 2>/dev/null) || return
  [[ "$owner" == "$(id -u)" ]] || \
    codex_safe_browser_profile_error "$label has the wrong owner" || return
  (( (8#$mode & 8#077) == 0 )) || \
    codex_safe_browser_profile_error "$label is accessible by group or world" || return
}

codex_safe_browser_profile_ensure_dir() {
  local path=$1 label=$2
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    install -d -m 700 "$path" || return
  fi
  codex_safe_browser_profile_check_dir "$path" "$label"
}

codex_safe_browser_profile_validate_root() {
  local host_home configured base real_home real_base real_root
  host_home=${CODEX_SAFE_HOST_HOME:-$HOME}
  configured=${CODEX_SAFE_BROWSER_PROFILE_ROOT-}
  [[ -n "$configured" && "$configured" == /* ]] || \
    codex_safe_browser_profile_error "persistent profile path is missing or relative" || return
  [[ "$configured" != *$'\n'* && "$configured" != *$'\r'* ]] || \
    codex_safe_browser_profile_error "persistent profile path contains control characters" || return

  real_home=$(realpath -e -- "$host_home" 2>/dev/null) || \
    codex_safe_browser_profile_error "cannot resolve the host home" || return
  base="$real_home/.local/state/codex-safe"
  [[ "$configured" == "$base/"* && "$configured" != "$base/" ]] || \
    codex_safe_browser_profile_error "persistent profile escaped $base" || return
  codex_safe_browser_profile_check_dir "$base" "browser state root" || return
  real_base=$(realpath -e -- "$base" 2>/dev/null) || return
  [[ "$real_base" == "$base" ]] || \
    codex_safe_browser_profile_error "browser state root resolves outside its fixed location" || return

  codex_safe_browser_profile_check_dir "$configured" "persistent browser profile" || return
  real_root=$(realpath -e -- "$configured" 2>/dev/null) || return
  [[ "$real_root" == "$real_base/"* ]] || \
    codex_safe_browser_profile_error "persistent browser profile escaped its state root" || return
  CODEX_SAFE_BROWSER_PROFILE_ROOT=$real_root
}

codex_safe_browser_profile_load() {
  local seed_file seed
  codex_safe_browser_profile_validate_root || return
  CODEX_SAFE_BROWSER_STATE="$CODEX_SAFE_BROWSER_PROFILE_ROOT/browser-state"
  codex_safe_browser_profile_check_dir \
    "$CODEX_SAFE_BROWSER_STATE" "persistent browser data directory" || return

  seed_file="$CODEX_SAFE_BROWSER_PROFILE_ROOT/fingerprint-seed"
  codex_safe_browser_profile_check_file "$seed_file" "fingerprint seed" || return
  IFS= read -r seed <"$seed_file" || return
  [[ "$seed" =~ ^[0-9a-f]{48}$ ]] || \
    codex_safe_browser_profile_error "fingerprint seed is invalid" || return
  CODEX_SAFE_FINGERPRINT_SEED=$seed
  export CODEX_SAFE_BROWSER_PROFILE_ROOT CODEX_SAFE_BROWSER_STATE
  export CODEX_SAFE_FINGERPRINT_SEED
}

codex_safe_browser_profile_acquire() {
  local host_home base lock_file seed_file seed
  host_home=${CODEX_SAFE_HOST_HOME:-$HOME}
  base="$host_home/.local/state/codex-safe"
  [[ ! -L "$host_home/.local" && ! -L "$host_home/.local/state" && ! -L "$base" ]] || \
    codex_safe_browser_profile_error "browser profile parent contains a symlink" || return
  codex_safe_browser_profile_ensure_dir "$base" "browser state root" || return

  [[ -n "${CODEX_SAFE_BROWSER_PROFILE_ROOT-}" ]] || \
    codex_safe_browser_profile_error "persistent profile path is not configured" || return
  [[ ! -L "$CODEX_SAFE_BROWSER_PROFILE_ROOT" ]] || \
    codex_safe_browser_profile_error "persistent browser profile is a symlink" || return
  codex_safe_browser_profile_ensure_dir \
    "$CODEX_SAFE_BROWSER_PROFILE_ROOT" "persistent browser profile" || return
  codex_safe_browser_profile_ensure_dir \
    "$CODEX_SAFE_BROWSER_PROFILE_ROOT/browser-state" \
    "persistent browser data directory" || return
  codex_safe_browser_profile_validate_root || return

  lock_file="$CODEX_SAFE_BROWSER_PROFILE_ROOT/profile.lock"
  [[ ! -L "$lock_file" ]] || \
    codex_safe_browser_profile_error "profile lock is a symlink" || return
  if [[ ! -e "$lock_file" ]]; then
    install -m 600 /dev/null "$lock_file" || return
  fi
  codex_safe_browser_profile_check_file "$lock_file" "profile lock" || return
  exec {CODEX_SAFE_BROWSER_PROFILE_LOCK_FD}<>"$lock_file"
  if ! flock -n "$CODEX_SAFE_BROWSER_PROFILE_LOCK_FD"; then
    exec {CODEX_SAFE_BROWSER_PROFILE_LOCK_FD}>&-
    codex_safe_browser_profile_error \
      "persistent profile is already in use; close the other CloakBrowser session"
    return 1
  fi

  seed_file="$CODEX_SAFE_BROWSER_PROFILE_ROOT/fingerprint-seed"
  if [[ ! -e "$seed_file" ]]; then
    seed=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
    [[ "$seed" =~ ^[0-9a-f]{48}$ ]] || \
      {
        codex_safe_browser_profile_release
        codex_safe_browser_profile_error "failed to generate fingerprint seed"
        return
      }
    install -m 600 /dev/null "$seed_file"
    printf '%s\n' "$seed" >"$seed_file"
  fi
  if ! codex_safe_browser_profile_load; then
    codex_safe_browser_profile_release
    return 1
  fi
}

codex_safe_browser_profile_release() {
  if [[ -n "${CODEX_SAFE_BROWSER_PROFILE_LOCK_FD-}" ]]; then
    flock -u "$CODEX_SAFE_BROWSER_PROFILE_LOCK_FD" 2>/dev/null || true
    exec {CODEX_SAFE_BROWSER_PROFILE_LOCK_FD}>&-
    CODEX_SAFE_BROWSER_PROFILE_LOCK_FD=''
  fi
}
