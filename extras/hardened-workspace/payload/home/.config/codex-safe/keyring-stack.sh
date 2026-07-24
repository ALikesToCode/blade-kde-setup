#!/usr/bin/env bash
# Private Secret Service broker shared by the outer launcher and the one-time
# MCP migration command. The broker runs outside Firejail so its encrypted
# files never become writable inside the agent sandbox. Only its per-session
# Unix socket is exposed to the jailed Codex process.

codex_safe_keyring_secure_dir() {
  local path=$1 owner mode
  [[ -d "$path" && ! -L "$path" ]] || return 1
  owner=$(stat -Lc '%u' -- "$path") || return 1
  mode=$(stat -Lc '%a' -- "$path") || return 1
  [[ "$owner" == "$(id -u)" ]] || return 1
  (( (8#$mode & 8#077) == 0 ))
}

codex_safe_keyring_start() {
  local socket keyring_home keyring_data keyring_config keyring_cache
  [[ -z "${CODEX_SAFE_KEYRING_DBUS_PID-}" && -z "${CODEX_SAFE_KEYRING_DAEMON_PID-}" ]] || return 1
  command -v dbus-daemon >/dev/null 2>&1 || return 1
  command -v busctl >/dev/null 2>&1 || return 1
  command -v gnome-keyring-daemon >/dev/null 2>&1 || return 1
  codex_safe_keyring_secure_dir "$CODEX_SAFE_KEYRING_RUNTIME_ROOT" || return 1
  codex_safe_keyring_secure_dir "$CODEX_SAFE_KEYRING_STATE" || return 1
  [[ -f "$CODEX_SAFE_KEYRING_PASSWORD" && ! -L "$CODEX_SAFE_KEYRING_PASSWORD" ]] || return 1
  [[ $(stat -Lc '%u' -- "$CODEX_SAFE_KEYRING_PASSWORD") == "$(id -u)" ]] || return 1
  [[ $(stat -Lc '%a' -- "$CODEX_SAFE_KEYRING_PASSWORD") == 600 ]] || return 1

  CODEX_SAFE_KEYRING_RUNTIME_DIR=$(mktemp -d "$CODEX_SAFE_KEYRING_RUNTIME_ROOT/session.XXXXXXXX") || return 1
  chmod 700 "$CODEX_SAFE_KEYRING_RUNTIME_DIR"
  install -d -m 700 \
    "$CODEX_SAFE_KEYRING_RUNTIME_DIR/control" \
    "$CODEX_SAFE_KEYRING_RUNTIME_DIR/run" \
    "$CODEX_SAFE_KEYRING_RUNTIME_DIR/cache"
  keyring_home="$CODEX_SAFE_KEYRING_STATE/home"
  keyring_data="$CODEX_SAFE_KEYRING_STATE/data"
  keyring_config="$CODEX_SAFE_KEYRING_STATE/config"
  keyring_cache="$CODEX_SAFE_KEYRING_RUNTIME_DIR/cache"
  install -d -m 700 "$keyring_home" "$keyring_data" "$keyring_config"

  socket="$CODEX_SAFE_KEYRING_RUNTIME_DIR/bus"
  dbus-daemon --session --address="unix:path=$socket" --nofork --nopidfile \
    >"$CODEX_SAFE_KEYRING_RUNTIME_DIR/dbus.log" 2>&1 &
  CODEX_SAFE_KEYRING_DBUS_PID=$!
  for _ in {1..100}; do
    [[ -S "$socket" ]] && break
    kill -0 "$CODEX_SAFE_KEYRING_DBUS_PID" 2>/dev/null || { codex_safe_keyring_stop; return 1; }
    sleep 0.05
  done
  [[ -S "$socket" ]] || { codex_safe_keyring_stop; return 1; }

  CODEX_SAFE_KEYRING_BUS_ADDRESS="unix:path=$socket"
  HOME="$keyring_home" \
    XDG_CONFIG_HOME="$keyring_config" \
    XDG_DATA_HOME="$keyring_data" \
    XDG_CACHE_HOME="$keyring_cache" \
    XDG_RUNTIME_DIR="$CODEX_SAFE_KEYRING_RUNTIME_DIR/run" \
    DBUS_SESSION_BUS_ADDRESS="$CODEX_SAFE_KEYRING_BUS_ADDRESS" \
    gnome-keyring-daemon --foreground --components=secrets \
      --control-directory="$CODEX_SAFE_KEYRING_RUNTIME_DIR/control" --unlock \
      <"$CODEX_SAFE_KEYRING_PASSWORD" \
      >"$CODEX_SAFE_KEYRING_RUNTIME_DIR/keyring.log" 2>&1 &
  CODEX_SAFE_KEYRING_DAEMON_PID=$!

  for _ in {1..160}; do
    if DBUS_SESSION_BUS_ADDRESS="$CODEX_SAFE_KEYRING_BUS_ADDRESS" \
        busctl --user --list --no-pager 2>/dev/null | grep -Fq org.freedesktop.secrets; then
      export CODEX_SAFE_KEYRING_RUNTIME_DIR CODEX_SAFE_KEYRING_BUS_ADDRESS
      export CODEX_SAFE_KEYRING_DBUS_PID CODEX_SAFE_KEYRING_DAEMON_PID
      return 0
    fi
    kill -0 "$CODEX_SAFE_KEYRING_DAEMON_PID" 2>/dev/null || { codex_safe_keyring_stop; return 1; }
    sleep 0.05
  done
  codex_safe_keyring_stop
  return 1
}

codex_safe_keyring_stop() {
  local pid
  for pid in "${CODEX_SAFE_KEYRING_DAEMON_PID-}" "${CODEX_SAFE_KEYRING_DBUS_PID-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  for pid in "${CODEX_SAFE_KEYRING_DAEMON_PID-}" "${CODEX_SAFE_KEYRING_DBUS_PID-}"; do
    [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true
  done
  if [[ -n "${CODEX_SAFE_KEYRING_RUNTIME_DIR-}" && \
        "$CODEX_SAFE_KEYRING_RUNTIME_DIR" == "$CODEX_SAFE_KEYRING_RUNTIME_ROOT/session."* ]]; then
    rm -rf -- "$CODEX_SAFE_KEYRING_RUNTIME_DIR"
  fi
  CODEX_SAFE_KEYRING_DAEMON_PID=''
  CODEX_SAFE_KEYRING_DBUS_PID=''
  CODEX_SAFE_KEYRING_RUNTIME_DIR=''
  CODEX_SAFE_KEYRING_BUS_ADDRESS=''
}
