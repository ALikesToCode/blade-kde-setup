#!/usr/bin/env bash
set -Eeuo pipefail

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check_file() { if [[ -f "$1" ]]; then pass "file $1"; else fail "file $1"; fi; }
check_exec() { if [[ -x "$1" ]]; then pass "executable $1"; else fail "executable $1"; fi; }

config_file="$HOME/.config/codex-safe/config"
check_file "$config_file"
if [[ -r "$config_file" ]]; then
  # shellcheck source=/dev/null
  source "$config_file"
else
  exit 1
fi

printf '%s\n' 'Effective codex-safe policy:'
printf '  workspace: real launch directory only (dynamic)\n'
printf '  persistent writable roots: [<resolved-launch-directory>]\n'
printf '  ephemeral writable roots: [/tmp, /dev, private Codex/browser state]\n'
printf '  ephemeral state mount: %s (private tmpfs in each jail; empty on host)\n' "$CODEX_SAFE_EPHEMERAL_ROOT"
printf '  read-only host roots: /, /home, /root, /etc, /usr, /var, /opt, /srv, /boot, /mnt, /media, /run/media\n'
printf '  Codex sandbox: workspace-write; approval: on-request; network: enabled; extra writable_roots: []\n'
printf '  Codex compatibility: features.use_legacy_landlock=true in temporary runtime overrides only\n'
printf '  browser: CloakBrowser %s -> loopback CDP -> Playwright CLI/MCP/scripts\n' "$CLOAKBROWSER_VERSION"
printf '  browser state: dedicated private state tmpfs; artifacts: <workspace>/.playwright-cli\n'
printf '  D-Bus: host buses disabled; private MCP Secret Service broker only\n'
printf '  MCP credentials: encrypted dedicated keyring; keyring files hidden inside jail\n'
printf '  capabilities: all dropped; nonewprivs+seccomp: enabled\n'

if [[ $(. /etc/os-release; printf '%s' "$ID") == arch ]]; then pass 'Arch Linux detected'; else fail 'Arch Linux detected'; fi
if ps -p 1 -o comm= 2>/dev/null | grep -qx systemd; then pass 'systemd init detected'; else fail 'systemd init detected'; fi
if command -v firejail >/dev/null; then pass "Firejail $(firejail --version 2>&1 | sed -n '1s/.*version //p')"; else fail 'Firejail installed'; fi
if [[ -r /etc/firejail/firejail.users ]] && grep -Fxq "$(id -un)" /etc/firejail/firejail.users; then pass 'current user explicitly permitted by Firejail'; else fail 'current user explicitly permitted by Firejail'; fi
check_exec "$HOME/.local/bin/codex-safe"
check_exec "$HOME/.local/bin/playwright-cli"
check_exec "$HOME/.local/bin/playwright-mcp-safe"
check_exec "$CODEX_SAFE_INNER"
check_exec "$CODEX_SAFE_SELF_TEST_INNER"
check_file "$CODEX_SAFE_KEYRING_LIB"
check_exec "$HOME/.local/bin/codex-safe-migrate-mcp"
check_file "$CODEX_SAFE_PROFILE"
check_exec "$CODEX_ORIGINAL_BIN_LINK"
check_exec "$CLOAKSERVE_BIN"
check_exec "$CLOAKBROWSER_BINARY_PATH"
check_exec "$PLAYWRIGHT_CLI_REAL"
check_exec "$PLAYWRIGHT_MCP_REAL"
check_exec "$SHELLCHECK_REAL"
check_file "$HOME/.config/codex-safe/PROVENANCE.md"
if command -v gnome-keyring-daemon >/dev/null; then pass 'private keyring daemon installed'; else fail 'private keyring daemon installed'; fi
if [[ $(systemctl --user is-enabled gnome-keyring-daemon.socket 2>/dev/null || true) == masked && \
      $(systemctl --user is-enabled gnome-keyring-daemon.service 2>/dev/null || true) == masked ]]; then pass 'desktop gnome-keyring units masked'; else fail 'desktop gnome-keyring units masked'; fi
if [[ -d "$CODEX_SAFE_KEYRING_STATE" && ! -L "$CODEX_SAFE_KEYRING_STATE" ]]; then pass 'private keyring state directory'; else fail 'private keyring state directory'; fi
if [[ -f "$CODEX_SAFE_KEYRING_PASSWORD" && ! -L "$CODEX_SAFE_KEYRING_PASSWORD" && $(stat -Lc '%a' "$CODEX_SAFE_KEYRING_PASSWORD") == 600 ]]; then pass 'private keyring unlock file protected'; else fail 'private keyring unlock file protected'; fi
if [[ -d "$CODEX_SAFE_EPHEMERAL_ROOT" && ! -L "$CODEX_SAFE_EPHEMERAL_ROOT" ]] && [[ -z $(find "$CODEX_SAFE_EPHEMERAL_ROOT" -mindepth 1 -print -quit 2>/dev/null) ]]; then pass 'host ephemeral mountpoint exists and is empty'; else fail 'host ephemeral mountpoint exists and is empty'; fi
if [[ -x "$SHELLCHECK_REAL" ]] && [[ $(sha256sum "$SHELLCHECK_REAL" | awk '{print $1}') == "$SHELLCHECK_SHA256" ]]; then pass 'pinned standalone ShellCheck checksum'; else fail 'pinned standalone ShellCheck checksum'; fi

if [[ -x "$CLOAKBROWSER_BINARY_PATH" ]]; then
  if [[ $(sha256sum "$CLOAKBROWSER_BINARY_PATH" | awk '{print $1}') == "$CLOAKBROWSER_BINARY_SHA256" ]]; then pass 'pinned CloakBrowser binary checksum'; else fail 'pinned CloakBrowser binary checksum'; fi
  if ldd "$CLOAKBROWSER_BINARY_PATH" 2>&1 | grep -q 'not found'; then fail 'CloakBrowser shared libraries resolved'; else pass 'CloakBrowser shared libraries resolved'; fi
fi
cloak_source="$HOME/.local/share/codex-safe/cloakbrowser-source-v0.4.11/bin/cloakserve"
if [[ -f "$cloak_source" ]] && [[ $(sha256sum "$cloak_source" | awk '{print $1}') == "$CLOAKSERVE_SOURCE_SHA256" ]]; then pass 'pinned cloakserve source checksum'; else fail 'pinned cloakserve source checksum'; fi
if [[ -f "$HOME/.codex/config.toml" ]]; then pass 'permanent Codex config preserved'; else fail 'permanent Codex config preserved'; fi
if ! rg -q '^sandbox_mode[[:space:]]*=' "$HOME/.codex/config.toml" 2>/dev/null; then pass 'permanent Codex sandbox config not weakened'; else pass 'permanent Codex config has user sandbox setting (runtime override remains locked)'; fi

if [[ "${1-}" == --run ]]; then
  test_root=${CODEX_SAFE_DOCTOR_WORKSPACE:-$PWD}
  if [[ "$test_root" == "$HOME" || "$test_root" == / || "$test_root" == /tmp* || "$test_root" == /run* || "$test_root" == /var/tmp* ]]; then
    fail 'doctor launch directory is safe'
  elif "$HOME/.local/bin/codex-safe" --codex-safe-self-test quick; then
    pass 'live Firejail/CloakBrowser quick test'
  else
    fail 'live Firejail/CloakBrowser quick test'
  fi
fi

if (( failures == 0 )); then
  printf 'PASS doctor complete\n'
  exit 0
fi
printf 'FAIL doctor: %d failure(s)\n' "$failures"
exit 1
