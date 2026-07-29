#!/usr/bin/env bash
# Runs only after Firejail has established the mandatory outer boundary. It
# starts CloakBrowser in this same process tree, prepares ephemeral Codex state,
# verifies the browser, and finally runs Codex as a supervised child.
set -Eeuo pipefail
umask 077

die() {
  printf 'codex-safe(inner): ERROR: %s\n' "$*" >&2
  exit 1
}

sanitize_browser_log() {
  sed -E 's#(https?|socks5)://[^/@[:space:]]+:[^/@[:space:]]+@#\1://<redacted>@#g' "$1" 2>/dev/null | tail -n 25 >&2 || true
}

top_mount_options() {
  findmnt --target "$1" --noheadings --output VFS-OPTIONS 2>/dev/null | tail -n 1
}

contains_mount_flag() {
  local options=$1 wanted=$2
  [[ ",$options," == *",$wanted,"* ]]
}

[[ "${CODEX_SAFE_ACTIVE-}" == 1 ]] || die "not entered through codex-safe"
[[ "${container-}" == firejail ]] || die "Firejail container marker is absent"
[[ -n "${CODEX_SAFE_WORKSPACE-}" && -d "$CODEX_SAFE_WORKSPACE" ]] || die "workspace is missing"
[[ "$(realpath -e -- "$PWD")" == "$CODEX_SAFE_WORKSPACE" ]] || die "working directory changed before sandbox entry"
[[ -r "${CODEX_SAFE_NESTED_DISPLAY_LIB-}" ]] || die "nested-display library is missing"
# shellcheck source=/dev/null
source "$CODEX_SAFE_NESTED_DISPLAY_LIB"

status_value=$(awk '$1=="NoNewPrivs:" {print $2}' /proc/self/status)
[[ "$status_value" == 1 ]] || die "NoNewPrivs is not active"
status_value=$(awk '$1=="Seccomp:" {print $2}' /proc/self/status)
[[ "$status_value" == 2 ]] || die "seccomp filter is not active"
status_value=$(awk '$1=="CapEff:" {print $2}' /proc/self/status)
[[ "$status_value" == 0000000000000000 ]] || die "effective capabilities were not fully dropped"
home_options=$(top_mount_options "$HOME")
contains_mount_flag "$home_options" ro || die "HOME is not mounted read-only"
workspace_options=$(top_mount_options "$CODEX_SAFE_WORKSPACE")
contains_mount_flag "$workspace_options" rw || die "workspace is not mounted read-write"
tmp_type=$(findmnt --target /tmp --noheadings --output FSTYPE 2>/dev/null | tail -n 1)
[[ "$tmp_type" == tmpfs ]] || die "/tmp is not a private tmpfs"
ephemeral_type=$(findmnt --target "$CODEX_SAFE_EPHEMERAL_ROOT" --noheadings --output FSTYPE 2>/dev/null | tail -n 1)
[[ "$ephemeral_type" == tmpfs ]] || die "dedicated Codex state path is not a private tmpfs"

workspace_probe="$CODEX_SAFE_WORKSPACE/.codex-safe-entry-probe-$CODEX_SAFE_SESSION_ID"
: >"$workspace_probe" || die "workspace write preflight failed"
rm -f -- "$workspace_probe"
outside_probe="$HOME/.codex-safe-entry-probe-$CODEX_SAFE_SESSION_ID"
if ( : >"$outside_probe" ) 2>/dev/null; then
  rm -f -- "$outside_probe"
  die "outer boundary allowed a persistent write outside the workspace"
fi

runtime_dir=$(mktemp -d "$CODEX_SAFE_EPHEMERAL_ROOT/session.XXXXXXXX") || die "cannot create private runtime directory"
chmod 700 "$runtime_dir"
browser_state="$runtime_dir/browser-state"
codex_home="$runtime_dir/codex-home"
codex_sqlite="$runtime_dir/codex-sqlite"
xdg_runtime="$runtime_dir/run"
xdg_cache="$runtime_dir/cache"
xdg_config="$runtime_dir/config"
browser_home="$runtime_dir/browser-home"
browser_cache="$runtime_dir/browser-cache"
browser_config="$runtime_dir/browser-config"
mkdir -m 700 "$browser_state" "$codex_home" "$codex_sqlite" "$xdg_runtime" "$xdg_cache" "$xdg_config" "$browser_home" "$browser_cache" "$browser_config"

cloak_pid=''
codex_pid=''
browser_pid=''
cleanup_done=0
# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  local rc=$?
  (( cleanup_done == 0 )) || return "$rc"
  cleanup_done=1
  set +e
  if [[ -n "$codex_pid" ]] && kill -0 "$codex_pid" 2>/dev/null; then
    kill -TERM "$codex_pid" 2>/dev/null || true
  fi
  if [[ -n "$cloak_pid" ]] && kill -0 "$cloak_pid" 2>/dev/null; then
    kill -TERM -- "-$cloak_pid" 2>/dev/null || kill -TERM "$cloak_pid" 2>/dev/null || true
    for _ in {1..30}; do
      kill -0 "$cloak_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$cloak_pid" 2>/dev/null; then
      kill -KILL -- "-$cloak_pid" 2>/dev/null || kill -KILL "$cloak_pid" 2>/dev/null || true
    fi
  fi
  if [[ "$runtime_dir" == "$CODEX_SAFE_EPHEMERAL_ROOT/session."* ]]; then
    rm -rf -- "$runtime_dir"
  fi
  return "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "${CODEX_SAFE_SIMULATE_CLOAK_MISSING-0}" != 1 ]] || die "simulated cloakserve unavailability"
[[ -x "$CLOAKSERVE_BIN" ]] || die "cloakserve is missing or not executable"
[[ -x "$CLOAKBROWSER_BINARY_PATH" ]] || die "signed patched Chromium is missing: $CLOAKBROWSER_BINARY_PATH"
cloak_binary_real=$(realpath -e -- "$CLOAKBROWSER_BINARY_PATH") || die "cannot resolve patched Chromium"
[[ "$cloak_binary_real" == "$HOME/.cloakbrowser/"* ]] || die "patched Chromium is outside the verified CloakBrowser cache"
[[ -n "${CLOAKBROWSER_BINARY_SHA256-}" ]] || die "pinned browser checksum is missing"
browser_sha=$(sha256sum "$cloak_binary_real" | awk '{print $1}')
[[ "$browser_sha" == "$CLOAKBROWSER_BINARY_SHA256" ]] || die "patched Chromium checksum mismatch"

port=$(python -S -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
[[ "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]] || die "failed to allocate a random loopback port"
fingerprint_seed=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
[[ "$fingerprint_seed" =~ ^[0-9a-f]{48}$ ]] || die "failed to generate fingerprint seed"

cloak_args=(
  "--port=$port"
  "--data-dir=$browser_state"
  "--idle-timeout=0"
  "--fingerprint=$fingerprint_seed"
  "--fingerprint-locale=$CODEX_SAFE_LOCALE"
  "--fingerprint-timezone=$CODEX_SAFE_TIMEZONE"
  "--password-store=basic"
)
browser_mode=headless
nested_display=''
nested_xauthority=''
case "${CODEX_SAFE_HEADED,,}" in
  true|1|yes)
    browser_mode=headed
    nested_display=${CODEX_SAFE_NESTED_DISPLAY-}
    nested_xauthority="$runtime_dir/nested.Xauthority"
    codex_safe_write_nested_authority \
      "$nested_xauthority" \
      "$nested_display" \
      "${CODEX_SAFE_NESTED_COOKIE-}" || die "cannot enter the visible nested display"
    cloak_args+=("--headless=false" "--ozone-platform=x11")
    ;;
  false|0|no)
    # cloakserve v0.4.11 tracks a headless boolean internally but its direct
    # Chromium spawn path does not currently emit Chromium's headless switch.
    # Pass it through explicitly; otherwise the verified binary tries Wayland.
    cloak_args+=("--headless=new")
    ;;
esac
unset CODEX_SAFE_NESTED_COOKIE CODEX_SAFE_NESTED_DISPLAY
if [[ -n "${CODEX_SAFE_PROXY-}" ]]; then
  cloak_args+=("--proxy-server=$CODEX_SAFE_PROXY")
fi

export CLOAKBROWSER_AUTO_UPDATE=false
export CLOAKBROWSER_BINARY_PATH=$cloak_binary_real
export CLOAKBROWSER_CACHE_DIR="$HOME/.cloakbrowser"
export CLOAKSERVE_IDLE_TIMEOUT=0
export CODEX_SAFE_BROWSER_MODE=$browser_mode
if [[ "$browser_mode" == headless ]]; then
  HOME="$browser_home" XDG_RUNTIME_DIR="$xdg_runtime" XDG_CACHE_HOME="$browser_cache" XDG_CONFIG_HOME="$browser_config" \
  DBUS_SESSION_BUS_ADDRESS=disabled: DBUS_SYSTEM_BUS_ADDRESS=disabled: \
    setsid env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY \
      "$CLOAKSERVE_BIN" "${cloak_args[@]}" >"$runtime_dir/cloakserve.log" 2>&1 &
else
  HOME="$browser_home" XDG_RUNTIME_DIR="$xdg_runtime" XDG_CACHE_HOME="$browser_cache" XDG_CONFIG_HOME="$browser_config" \
  DISPLAY="$nested_display" XAUTHORITY="$nested_xauthority" \
  DBUS_SESSION_BUS_ADDRESS=disabled: DBUS_SYSTEM_BUS_ADDRESS=disabled: \
    setsid "$CLOAKSERVE_BIN" "${cloak_args[@]}" >"$runtime_dir/cloakserve.log" 2>&1 &
fi
cloak_pid=$!

health_url="http://127.0.0.1:$port/json/version?fingerprint=$fingerprint_seed&timezone=$CODEX_SAFE_TIMEZONE&locale=$CODEX_SAFE_LOCALE"
deadline=$((SECONDS + CODEX_SAFE_CDP_TIMEOUT_SECONDS))
health_ok=0
while (( SECONDS < deadline )); do
  if ! kill -0 "$cloak_pid" 2>/dev/null; then
    sanitize_browser_log "$runtime_dir/cloakserve.log"
    die "cloakserve exited before the CDP endpoint became healthy"
  fi
  if curl --fail --silent --show-error --max-time 2 "$health_url" >"$runtime_dir/cdp-version.json" 2>/dev/null; then
    health_ok=1
    break
  fi
  sleep 0.2
done
(( health_ok == 1 )) || { sanitize_browser_log "$runtime_dir/cloakserve.log"; die "CloakBrowser CDP health check timed out"; }

listen_addresses=$(ss -H -ltn "sport = :$port" | awk '{print $4}')
[[ -n "$listen_addresses" ]] || die "cloakserve is not listening"
while IFS= read -r address; do
  [[ "$address" == "127.0.0.1:$port" ]] || die "cloakserve is not loopback-only: $address"
done <<<"$listen_addresses"

fingerprint_seen=0
while IFS= read -r -d '' token; do
  [[ "$token" == "--fingerprint=$fingerprint_seed" ]] && fingerprint_seen=1
done <"/proc/$cloak_pid/cmdline"
(( fingerprint_seen == 1 )) || die "cloakserve launch lacks the generated fingerprint argument"

curl --fail --silent --show-error --max-time 2 "http://127.0.0.1:$port/" >"$runtime_dir/cloak-status.json" || die "cannot read cloakserve process status"
browser_pid=$(jq -er --arg seed "$fingerprint_seed" '.processes[$seed].pid | select(type=="number")' "$runtime_dir/cloak-status.json") || die "generated fingerprint process is absent from cloakserve status"
status_seed=$(jq -er --arg seed "$fingerprint_seed" '.processes[$seed].seed' "$runtime_dir/cloak-status.json") || die "cloakserve status lacks the generated fingerprint seed"
status_locale=$(jq -er --arg seed "$fingerprint_seed" '.processes[$seed].locale' "$runtime_dir/cloak-status.json") || die "cloakserve status lacks locale"
status_timezone=$(jq -er --arg seed "$fingerprint_seed" '.processes[$seed].timezone' "$runtime_dir/cloak-status.json") || die "cloakserve status lacks timezone"
[[ "$status_seed" == "$fingerprint_seed" ]] || die "cloakserve status fingerprint mismatch"
[[ "$status_locale" == "$CODEX_SAFE_LOCALE" ]] || die "cloakserve status locale mismatch"
[[ "$status_timezone" == "$CODEX_SAFE_TIMEZONE" ]] || die "cloakserve status timezone mismatch"
browser_exe=$(readlink -f -- "/proc/$browser_pid/exe" 2>/dev/null || true)
[[ "$browser_exe" == "$cloak_binary_real" ]] || die "cloakserve-reported process is not the patched Chromium executable"
browser_profile=$(realpath -e -- "$browser_state/$fingerprint_seed" 2>/dev/null) || die "private browser profile was not created"
[[ "$browser_profile" == "$browser_state/"* ]] || die "browser profile escaped private runtime storage"

server_headless_flag=''
while IFS= read -r -d '' token; do
  case "$token" in --headless|--headless=*) server_headless_flag=$token ;; esac
done <"/proc/$cloak_pid/cmdline"
browser_parent_pid=$(awk '$1=="PPid:" {print $2}' "/proc/$browser_pid/status")
[[ "$browser_parent_pid" =~ ^[0-9]+$ ]] || die "cannot resolve the CloakBrowser parent process"
server_display=''
while IFS= read -r -d '' entry; do
  case "$entry" in DISPLAY=*) server_display=${entry#DISPLAY=} ;; esac
done <"/proc/$browser_parent_pid/environ"
headless_flag=''
while IFS= read -r -d '' token; do
  case "$token" in --headless|--headless=*) headless_flag=$token ;; esac
done <"/proc/$browser_pid/cmdline"
if [[ "$browser_mode" == headless ]]; then
  [[ "$server_headless_flag" == "--headless=new" ]] || die "cloakserve did not receive explicit headless mode"
  [[ -z "$server_display" ]] || die "headless cloakserve unexpectedly has a desktop display"
else
  [[ "$server_headless_flag" == "--headless=false" ]] || die "cloakserve did not receive explicit headed mode"
  [[ "$server_display" == "$nested_display" ]] || \
    die "headed cloakserve is not using its visible nested display"
  [[ -z "$headless_flag" ]] || die "headed Chromium unexpectedly retained a headless launch flag"
fi

artifact_dir="$CODEX_SAFE_WORKSPACE/.playwright-cli"
install -d -m 700 "$artifact_dir"

endpoint="http://127.0.0.1:$port?fingerprint=$fingerprint_seed&timezone=$CODEX_SAFE_TIMEZONE&locale=$CODEX_SAFE_LOCALE"
playwright_mcp_config="$runtime_dir/playwright-mcp.json"
jq -n \
  --arg endpoint "$endpoint" \
  --arg output "$artifact_dir" \
  --arg locale "$CODEX_SAFE_LOCALE" \
  --arg timezone "$CODEX_SAFE_TIMEZONE" \
  '{browser:{browserName:"chromium",isolated:true,cdpEndpoint:$endpoint,cdpTimeout:20000,contextOptions:{locale:$locale,timezoneId:$timezone,acceptDownloads:true}},outputDir:$output,saveSession:true,allowUnrestrictedFileAccess:false}' \
  >"$playwright_mcp_config"
chmod 600 "$playwright_mcp_config"

export CLOAK_CDP_ENDPOINT=$endpoint
export PLAYWRIGHT_MCP_CDP_ENDPOINT=$endpoint
export PLAYWRIGHT_MCP_CONFIG=$playwright_mcp_config
export PLAYWRIGHT_MCP_OUTPUT_DIR=$artifact_dir
export PLAYWRIGHT_CLI_OUTPUT_DIR=$artifact_dir
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export PLAYWRIGHT_BROWSERS_PATH="$runtime_dir/no-stock-browsers"
export CODEX_SAFE_CLOAKSERVE_PID=$cloak_pid
export CODEX_SAFE_BROWSER_PID=$browser_pid
export CODEX_SAFE_CDP_PORT=$port
export CODEX_SAFE_BROWSER_EXE=$cloak_binary_real
export CODEX_SAFE_BROWSER_STATE=$browser_state
export CODEX_SAFE_FINGERPRINT_SEED=$fingerprint_seed
export CODEX_SAFE_RUNTIME_DIR=$runtime_dir
export XDG_RUNTIME_DIR=$xdg_runtime
export XDG_CACHE_HOME=$xdg_cache
export XDG_CONFIG_HOME=$xdg_config
[[ "${CODEX_SAFE_KEYRING_BUS_ADDRESS-}" == \
    "unix:path=$CODEX_SAFE_KEYRING_RUNTIME_ROOT/session."*'/bus' ]] || \
  die "private MCP credential bus address is invalid"
keyring_bus_socket=${CODEX_SAFE_KEYRING_BUS_ADDRESS#unix:path=}
[[ -S "$keyring_bus_socket" ]] || die "private MCP credential bus socket is unavailable"
export DBUS_SESSION_BUS_ADDRESS=$CODEX_SAFE_KEYRING_BUS_ADDRESS
export DBUS_SYSTEM_BUS_ADDRESS=disabled:
if ! busctl --user --list --no-pager 2>/dev/null | grep -Fq org.freedesktop.secrets; then
  die "private MCP credential service is unavailable"
fi

if [[ -n "${NODE_OPTIONS-}" ]]; then
  export NODE_OPTIONS="--require=$CODEX_SAFE_NODE_PRELOAD $NODE_OPTIONS"
else
  export NODE_OPTIONS="--require=$CODEX_SAFE_NODE_PRELOAD"
fi
if [[ -n "${PYTHONPATH-}" ]]; then
  export PYTHONPATH="$CODEX_SAFE_PYTHON_DIR:$PYTHONPATH"
else
  export PYTHONPATH="$CODEX_SAFE_PYTHON_DIR"
fi

if [[ -n "${CODEX_SAFE_SELF_TEST_MODE-}" ]]; then
  "$CODEX_SAFE_SELF_TEST_INNER" "$CODEX_SAFE_SELF_TEST_MODE"
  exit $?
fi

[[ -r "$HOME/.codex/config.toml" ]] || die "original Codex configuration is unreadable"
install -m 600 "$HOME/.codex/config.toml" "$codex_home/config.toml"
if [[ -r "$HOME/.codex/auth.json" ]]; then
  install -m 600 "$HOME/.codex/auth.json" "$codex_home/auth.json"
elif [[ -z "${OPENAI_API_KEY-}" ]]; then
  die "no supported Codex authentication source is available"
fi
if [[ -r "$HOME/.codex/AGENTS.md" ]]; then
  install -m 600 "$HOME/.codex/AGENTS.md" "$codex_home/AGENTS.md"
fi
for linked in skills plugins vendor_imports packages; do
  if [[ -e "$HOME/.codex/$linked" ]]; then
    ln -s "$HOME/.codex/$linked" "$codex_home/$linked"
  fi
done
for copied in .codex-global-state.json installation_id version.json models_cache.json; do
  if [[ -f "$HOME/.codex/$copied" ]]; then
    install -m 600 "$HOME/.codex/$copied" "$codex_home/$copied"
  fi
done

export CODEX_HOME=$codex_home
export CODEX_SQLITE_HOME=$codex_sqlite

codex_policy_args=(
  -C "$CODEX_SAFE_WORKSPACE"
  --sandbox workspace-write
  --ask-for-approval on-request
  -c 'sandbox_mode="workspace-write"'
  -c 'approval_policy="on-request"'
  -c 'sandbox_workspace_write.network_access=true'
  -c 'sandbox_workspace_write.writable_roots=[]'
  -c 'sandbox_workspace_write.exclude_tmpdir_env_var=false'
  -c 'sandbox_workspace_write.exclude_slash_tmp=false'
  -c 'features.use_legacy_landlock=true'
  -c 'mcp_oauth_credentials_store="keyring"'
  -c 'shell_environment_policy.exclude=["DBUS_SESSION_BUS_ADDRESS","CODEX_SAFE_KEYRING_BUS_ADDRESS","CODEX_SAFE_KEYRING_RUNTIME_ROOT","CODEX_SAFE_KEYRING_STATE","CODEX_SAFE_KEYRING_PASSWORD"]'
  -c "mcp_servers.playwright_safe.command=\"$PLAYWRIGHT_MCP_SAFE\""
  -c 'mcp_servers.playwright_safe.args=[]'
  -c 'mcp_servers.playwright_safe.startup_timeout_sec=30'
  -c 'mcp_servers.playwright_safe.env.CODEX_SAFE_ACTIVE="1"'
  -c "mcp_servers.playwright_safe.env.CODEX_SAFE_BROWSER_MODE=\"$browser_mode\""
  -c "mcp_servers.playwright_safe.env.CLOAK_CDP_ENDPOINT=\"$endpoint\""
  -c "mcp_servers.playwright_safe.env.PLAYWRIGHT_MCP_CONFIG=\"$playwright_mcp_config\""
  -c "mcp_servers.playwright_safe.env.PLAYWRIGHT_MCP_OUTPUT_DIR=\"$artifact_dir\""
  -c 'shell_environment_policy.set.CODEX_SAFE_ACTIVE="1"'
  -c "shell_environment_policy.set.CODEX_SAFE_SESSION_ID=\"$CODEX_SAFE_SESSION_ID\""
  -c "shell_environment_policy.set.CODEX_SAFE_BROWSER_MODE=\"$browser_mode\""
  -c "shell_environment_policy.set.CLOAK_CDP_ENDPOINT=\"$endpoint\""
  -c "shell_environment_policy.set.PLAYWRIGHT_MCP_CDP_ENDPOINT=\"$endpoint\""
  -c "shell_environment_policy.set.PLAYWRIGHT_MCP_CONFIG=\"$playwright_mcp_config\""
  -c "shell_environment_policy.set.PLAYWRIGHT_MCP_OUTPUT_DIR=\"$artifact_dir\""
  -c "shell_environment_policy.set.PLAYWRIGHT_CLI_OUTPUT_DIR=\"$artifact_dir\""
  -c "shell_environment_policy.set.XDG_RUNTIME_DIR=\"$xdg_runtime\""
)

# Bash redirects stdin from /dev/null for asynchronous commands when job control
# is disabled, unless the command has an explicit stdin redirection. Keep Codex
# supervised for cleanup while preserving the caller's real terminal.
"$CODEX_SAFE_ORIGINAL_BIN" "${codex_policy_args[@]}" "$@" 0<&0 &
codex_pid=$!
set +e
wait "$codex_pid"
rc=$?
set -e
codex_pid=''
exit "$rc"
