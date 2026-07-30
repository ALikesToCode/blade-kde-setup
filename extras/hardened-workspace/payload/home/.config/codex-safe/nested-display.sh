#!/usr/bin/env bash
# Shared nested-display lifecycle for visible CloakBrowser sessions. Xephyr is
# the only process connected to KDE; Chromium receives a separate X display and
# authority cookie. A one-way text bridge copies the host clipboard into Xephyr
# without exposing the nested clipboard back to KDE.

codex_safe_nested_display_error() {
  printf 'nested-display: ERROR: %s\n' "$*" >&2
  return 1
}

codex_safe_validate_xauthority() {
  local authority=$1 owner mode
  [[ -f "$authority" && ! -L "$authority" ]] || return 1
  owner=$(stat -Lc '%u' -- "$authority" 2>/dev/null) || return 1
  mode=$(stat -Lc '%a' -- "$authority" 2>/dev/null) || return 1
  [[ "$owner" == "$(id -u)" ]] || return 1
  (( (8#$mode & 8#077) == 0 ))
}

codex_safe_resolve_host_x11() {
  local display=${DISPLAY-} authority=${XAUTHORITY-}
  local runtime_root
  local session_file display_number candidate newest_mtime=-1 candidate_mtime
  local -a session_files authority_files

  runtime_root="/run/user/$(id -u)"
  if [[ -n "$display" || -n "$authority" ]]; then
    [[ -n "$display" && -n "$authority" ]] || \
      codex_safe_nested_display_error "DISPLAY and XAUTHORITY must be supplied together" || return
    [[ "$display" =~ ^:([0-9]+)(\.[0-9]+)?$ ]] || \
      codex_safe_nested_display_error "headed mode requires a local X11 display" || return
    display_number=${BASH_REMATCH[1]}
    [[ -S "/tmp/.X11-unix/X$display_number" ]] || \
      codex_safe_nested_display_error "host X11 socket is missing for $display" || return
    codex_safe_validate_xauthority "$authority" || \
      codex_safe_nested_display_error "host Xauthority file is unsafe or unreadable" || return
    timeout 3 env DISPLAY="$display" XAUTHORITY="$authority" xdpyinfo >/dev/null 2>&1 || \
      codex_safe_nested_display_error "cannot authenticate to the host KDE X11 display" || return
    CODEX_SAFE_HOST_DISPLAY=$display
    CODEX_SAFE_HOST_XAUTHORITY=$authority
    return 0
  fi

  session_files=("$runtime_root"/KSMserver__*)
  authority_files=("$runtime_root"/xauth_*)
  for session_file in "${session_files[@]}"; do
    [[ -f "$session_file" ]] || continue
    display_number=${session_file##*__}
    [[ "$display_number" =~ ^[0-9]+$ ]] || continue
    [[ -S "/tmp/.X11-unix/X$display_number" ]] || continue
    display=":$display_number"
    authority=''
    newest_mtime=-1
    for candidate in "${authority_files[@]}"; do
      codex_safe_validate_xauthority "$candidate" || continue
      timeout 3 env DISPLAY="$display" XAUTHORITY="$candidate" xdpyinfo >/dev/null 2>&1 || continue
      candidate_mtime=$(stat -Lc '%Y' -- "$candidate") || continue
      if (( candidate_mtime > newest_mtime )); then
        authority=$candidate
        newest_mtime=$candidate_mtime
      fi
    done
    [[ -n "$authority" ]] || continue
    if [[ -n "${CODEX_SAFE_HOST_DISPLAY-}" && "$CODEX_SAFE_HOST_DISPLAY" != "$display" ]]; then
      codex_safe_nested_display_error "multiple usable KDE X11 displays found; set DISPLAY and XAUTHORITY explicitly" || return
    fi
    CODEX_SAFE_HOST_DISPLAY=$display
    CODEX_SAFE_HOST_XAUTHORITY=$authority
  done

  [[ -n "${CODEX_SAFE_HOST_DISPLAY-}" && -n "${CODEX_SAFE_HOST_XAUTHORITY-}" ]] || \
    codex_safe_nested_display_error "cannot discover the active KDE X11 display" || return
}

codex_safe_verify_xephyr() {
  local resolved hash
  [[ -x "${XEPHYR_BIN-}" ]] || codex_safe_nested_display_error "Xephyr is missing" || return
  [[ -n "${XEPHYR_BINARY_SHA256-}" ]] || \
    codex_safe_nested_display_error "pinned Xephyr checksum is missing" || return
  resolved=$(realpath -e -- "$XEPHYR_BIN") || \
    codex_safe_nested_display_error "cannot resolve Xephyr" || return
  hash=$(sha256sum "$resolved" | awk '{print $1}')
  [[ "$hash" == "$XEPHYR_BINARY_SHA256" ]] || \
    codex_safe_nested_display_error "Xephyr checksum mismatch" || return
  XEPHYR_BIN=$resolved
}

codex_safe_verify_clipboard_bridge() {
  local bridge=${CODEX_SAFE_CLIPBOARD_BRIDGE-} xclip=${CODEX_SAFE_XCLIP_BIN-}
  local owner mode resolved
  [[ -f "$bridge" && ! -L "$bridge" && -r "$bridge" ]] || \
    codex_safe_nested_display_error "clipboard bridge is missing or unsafe" || return
  owner=$(stat -Lc '%u' -- "$bridge" 2>/dev/null) || return
  mode=$(stat -Lc '%a' -- "$bridge" 2>/dev/null) || return
  [[ "$owner" == "$(id -u)" ]] || \
    codex_safe_nested_display_error "clipboard bridge has the wrong owner" || return
  (( (8#$mode & 8#022) == 0 )) || \
    codex_safe_nested_display_error "clipboard bridge is group/world-writable" || return
  CODEX_SAFE_CLIPBOARD_BRIDGE=$(realpath -e -- "$bridge") || return

  [[ -x "$xclip" && ! -L "$xclip" ]] || \
    codex_safe_nested_display_error "xclip is missing or unsafe" || return
  resolved=$(realpath -e -- "$xclip") || return
  [[ "$resolved" == /usr/bin/xclip ]] || \
    codex_safe_nested_display_error "xclip resolved outside /usr/bin" || return
  CODEX_SAFE_XCLIP_BIN=$resolved
}

codex_safe_verify_nested_window_manager() {
  local manager=${CODEX_SAFE_NESTED_WINDOW_MANAGER-} owner mode
  [[ -f "$manager" && ! -L "$manager" && -r "$manager" ]] || \
    codex_safe_nested_display_error "nested window manager is missing or unsafe" || return
  owner=$(stat -Lc '%u' -- "$manager" 2>/dev/null) || return
  mode=$(stat -Lc '%a' -- "$manager" 2>/dev/null) || return
  [[ "$owner" == "$(id -u)" ]] || \
    codex_safe_nested_display_error "nested window manager has the wrong owner" || return
  (( (8#$mode & 8#022) == 0 )) || \
    codex_safe_nested_display_error "nested window manager is group/world-writable" || return
  CODEX_SAFE_NESTED_WINDOW_MANAGER=$(realpath -e -- "$manager") || return
}

codex_safe_write_nested_authority() {
  local authority=$1 display=$2 cookie=$3
  [[ "$display" =~ ^:[0-9]+$ ]] || \
    codex_safe_nested_display_error "invalid nested display" || return
  [[ "$cookie" =~ ^[0-9a-f]{32}$ ]] || \
    codex_safe_nested_display_error "invalid nested display cookie" || return
  install -m 600 /dev/null "$authority"
  xauth -f "$authority" add "$display" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1 || \
    codex_safe_nested_display_error "cannot create nested Xauthority file" || return
}

codex_safe_start_clipboard_bridge() {
  local state_root=$1 ready_file deadline
  codex_safe_verify_clipboard_bridge || return
  ready_file="$state_root/clipboard-bridge.ready"
  rm -f -- "$ready_file"
  DBUS_SESSION_BUS_ADDRESS=disabled: \
  DBUS_SYSTEM_BUS_ADDRESS=disabled: \
    python -I -S "$CODEX_SAFE_CLIPBOARD_BRIDGE" \
      --host-display "$CODEX_SAFE_HOST_DISPLAY" \
      --host-authority "$CODEX_SAFE_HOST_XAUTHORITY" \
      --nested-display "$CODEX_SAFE_NESTED_DISPLAY" \
      --nested-authority "$CODEX_SAFE_NESTED_XAUTHORITY" \
      --xclip "$CODEX_SAFE_XCLIP_BIN" \
      --ready-file "$ready_file" >"$state_root/clipboard-bridge.log" 2>&1 &
  CODEX_SAFE_CLIPBOARD_BRIDGE_PID=$!

  deadline=$((SECONDS + 10))
  while (( SECONDS < deadline )); do
    kill -0 "$CODEX_SAFE_CLIPBOARD_BRIDGE_PID" 2>/dev/null || {
      codex_safe_nested_display_error "clipboard bridge exited during startup"
      return 1
    }
    [[ -f "$ready_file" ]] && return 0
    sleep 0.1
  done
  codex_safe_nested_display_error "clipboard bridge startup timed out"
}

codex_safe_start_nested_window_manager() {
  local state_root=$1 ready_file deadline
  codex_safe_verify_nested_window_manager || return
  ready_file="$state_root/window-manager.ready"
  rm -f -- "$ready_file"
  DISPLAY="$CODEX_SAFE_NESTED_DISPLAY" \
  XAUTHORITY="$CODEX_SAFE_NESTED_XAUTHORITY" \
  DBUS_SESSION_BUS_ADDRESS=disabled: \
  DBUS_SYSTEM_BUS_ADDRESS=disabled: \
    python -I -S "$CODEX_SAFE_NESTED_WINDOW_MANAGER" \
      --ready-file "$ready_file" >"$state_root/window-manager.log" 2>&1 &
  CODEX_SAFE_NESTED_WM_PID=$!

  deadline=$((SECONDS + 10))
  while (( SECONDS < deadline )); do
    kill -0 "$CODEX_SAFE_NESTED_WM_PID" 2>/dev/null || {
      codex_safe_nested_display_error "nested window manager exited during startup"
      return 1
    }
    [[ -f "$ready_file" ]] && return 0
    sleep 0.1
  done
  codex_safe_nested_display_error "nested window manager startup timed out"
}

codex_safe_start_nested_display() {
  local lock_root=$1 state_root=$2 display_number socket_path deadline lock_path
  local candidate lock_owner lock_mode display_ready=0

  codex_safe_verify_xephyr || return
  codex_safe_resolve_host_x11 || return
  [[ ! -L "$lock_root" ]] || \
    codex_safe_nested_display_error "nested display lock root must not be a symlink" || return
  install -d -m 700 "$lock_root" "$state_root"
  lock_owner=$(stat -Lc '%u' -- "$lock_root") || return
  lock_mode=$(stat -Lc '%a' -- "$lock_root") || return
  [[ "$lock_owner" == "$(id -u)" ]] || \
    codex_safe_nested_display_error "nested display lock root has the wrong owner" || return
  (( (8#$lock_mode & 8#077) == 0 )) || \
    codex_safe_nested_display_error "nested display lock root is not private" || return

  CODEX_SAFE_NESTED_DISPLAY=''
  CODEX_SAFE_NESTED_DISPLAY_LOCK=''
  for ((candidate=90; candidate<=189; candidate++)); do
    lock_path="$lock_root/display-$candidate.lock"
    if [[ -d "$lock_path" && ! -S "/tmp/.X11-unix/X$candidate" && \
          ! -e "/tmp/.X$candidate-lock" ]]; then
      rmdir "$lock_path" 2>/dev/null || true
    fi
    if mkdir "$lock_path" 2>/dev/null; then
      if [[ ! -S "/tmp/.X11-unix/X$candidate" && ! -e "/tmp/.X$candidate-lock" ]]; then
        CODEX_SAFE_NESTED_DISPLAY=":$candidate"
        CODEX_SAFE_NESTED_DISPLAY_LOCK=$lock_path
        break
      fi
      rmdir "$lock_path" 2>/dev/null || true
    fi
  done
  [[ -n "$CODEX_SAFE_NESTED_DISPLAY" ]] || \
    codex_safe_nested_display_error "no free nested X11 display is available" || return

  CODEX_SAFE_NESTED_COOKIE=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  CODEX_SAFE_NESTED_XAUTHORITY="$state_root/nested.Xauthority"
  codex_safe_write_nested_authority \
    "$CODEX_SAFE_NESTED_XAUTHORITY" \
    "$CODEX_SAFE_NESTED_DISPLAY" \
    "$CODEX_SAFE_NESTED_COOKIE" || return

  display_number=${CODEX_SAFE_NESTED_DISPLAY#:}
  socket_path="/tmp/.X11-unix/X$display_number"
  DISPLAY="$CODEX_SAFE_HOST_DISPLAY" \
  XAUTHORITY="$CODEX_SAFE_HOST_XAUTHORITY" \
    "$XEPHYR_BIN" "$CODEX_SAFE_NESTED_DISPLAY" \
      -auth "$CODEX_SAFE_NESTED_XAUTHORITY" \
      -screen 1440x900 \
      -resizeable \
      -br \
      -noreset \
      -nolisten tcp \
      -name cloakbrowser-automation \
      -title 'CloakBrowser Automation' \
      >"$state_root/xephyr.log" 2>&1 &
  CODEX_SAFE_XEPHYR_PID=$!

  deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    kill -0 "$CODEX_SAFE_XEPHYR_PID" 2>/dev/null || {
      codex_safe_nested_display_error "Xephyr exited during startup"
      return 1
    }
    if [[ -S "$socket_path" ]] && \
        timeout 2 env DISPLAY="$CODEX_SAFE_NESTED_DISPLAY" \
          XAUTHORITY="$CODEX_SAFE_NESTED_XAUTHORITY" xdpyinfo >/dev/null 2>&1; then
      display_ready=1
      break
    fi
    sleep 0.1
  done
  (( display_ready == 1 )) || \
    codex_safe_nested_display_error "Xephyr startup timed out" || return
  codex_safe_start_nested_window_manager "$state_root" || return
  codex_safe_start_clipboard_bridge "$state_root"
}

codex_safe_stop_nested_display() {
  if [[ -n "${CODEX_SAFE_CLIPBOARD_BRIDGE_PID-}" ]] && \
      kill -0 "$CODEX_SAFE_CLIPBOARD_BRIDGE_PID" 2>/dev/null; then
    kill -TERM "$CODEX_SAFE_CLIPBOARD_BRIDGE_PID" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$CODEX_SAFE_CLIPBOARD_BRIDGE_PID" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$CODEX_SAFE_CLIPBOARD_BRIDGE_PID" 2>/dev/null; then
      kill -KILL "$CODEX_SAFE_CLIPBOARD_BRIDGE_PID" 2>/dev/null || true
    fi
  fi
  if [[ -n "${CODEX_SAFE_NESTED_WM_PID-}" ]] && \
      kill -0 "$CODEX_SAFE_NESTED_WM_PID" 2>/dev/null; then
    kill -TERM "$CODEX_SAFE_NESTED_WM_PID" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$CODEX_SAFE_NESTED_WM_PID" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$CODEX_SAFE_NESTED_WM_PID" 2>/dev/null; then
      kill -KILL "$CODEX_SAFE_NESTED_WM_PID" 2>/dev/null || true
    fi
  fi
  if [[ -n "${CODEX_SAFE_XEPHYR_PID-}" ]] && kill -0 "$CODEX_SAFE_XEPHYR_PID" 2>/dev/null; then
    kill -TERM "$CODEX_SAFE_XEPHYR_PID" 2>/dev/null || true
    for _ in {1..30}; do
      kill -0 "$CODEX_SAFE_XEPHYR_PID" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$CODEX_SAFE_XEPHYR_PID" 2>/dev/null; then
      kill -KILL "$CODEX_SAFE_XEPHYR_PID" 2>/dev/null || true
    fi
  fi
  if [[ -n "${CODEX_SAFE_NESTED_DISPLAY_LOCK-}" && \
        "$CODEX_SAFE_NESTED_DISPLAY_LOCK" == */display-*.lock ]]; then
    rmdir "$CODEX_SAFE_NESTED_DISPLAY_LOCK" 2>/dev/null || true
  fi
  CODEX_SAFE_CLIPBOARD_BRIDGE_PID=''
  CODEX_SAFE_NESTED_WM_PID=''
  CODEX_SAFE_XEPHYR_PID=''
  CODEX_SAFE_NESTED_DISPLAY_LOCK=''
}
