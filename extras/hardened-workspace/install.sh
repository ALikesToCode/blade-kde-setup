#!/usr/bin/env bash
# Idempotent user-level installer for the staged codex-safe payload. System
# packages and /etc/firejail/firejail.users are handled separately with sudo.
set -Eeuo pipefail
umask 077

die() { printf 'install.sh: ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf 'install.sh: %s\n' "$*"; }

action=${1:-stage}
case "$action" in stage|integrate-shell) ;; *) die "usage: $0 [stage|integrate-shell]" ;; esac
[[ $(id -u) -ne 0 ]] || die "run as the target user, not root"
[[ -n "${HOME-}" && -d "$HOME" ]] || die "HOME is invalid"

root=$(realpath -e -- "$(dirname -- "${BASH_SOURCE[0]}")")
payload="$root/payload/home"
[[ -d "$payload" ]] || die "payload directory is missing"
backup_root="$HOME/.config/codex-safe/backups"
manifest="$backup_root/manifest.tsv"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir="$backup_root/$timestamp"
install -d -m 700 "$backup_root" "$backup_dir"
touch "$manifest"
chmod 600 "$manifest"

record() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$manifest"
}

backup_target() {
  local target=$1 backup
  # Preserve exactly one pre-install baseline per pathname. Repair reinstalls
  # must not turn files created by this installer into misleading backups or
  # replace an older genuine backup with an intermediate codex-safe version.
  if awk -F '\t' -v target="$target" '$2==target {found=1} END {exit !found}' "$manifest"; then
    return
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    backup="$backup_dir$target"
    install -d -m 700 "$(dirname -- "$backup")"
    cp -a -- "$target" "$backup"
    record BACKUP "$target" "$backup"
  else
    record CREATED "$target" '-'
  fi
}

install_payload_file() {
  local relative=$1 mode=$2 source target
  source="$payload/$relative"
  target="$HOME/$relative"
  [[ -f "$source" ]] || die "missing payload file: $source"
  mkdir -p "$(dirname -- "$target")"
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    chmod "$mode" "$target"
    return
  fi
  backup_target "$target"
  install -m "$mode" "$source" "$target"
}

append_block() {
  local target=$1 begin=$2 end=$3 content=$4
  if [[ -f "$target" ]] && grep -Fxq "$begin" "$target"; then
    note "marker already present in $target"
    return
  fi
  backup_target "$target"
  mkdir -p "$(dirname -- "$target")"
  touch "$target"
  if [[ -s "$target" ]]; then printf '\n' >>"$target"; fi
  printf '%s\n%s\n%s\n' "$begin" "$content" "$end" >>"$target"
}

if [[ "$action" == stage ]]; then
  os_id=$(. /etc/os-release; printf '%s' "$ID")
  [[ "$os_id" == arch || "$os_id" == artix ]] || die "this installer supports Arch/Artix only"
  for command_name in firejail node npm npx python pipx jq curl ss findmnt git realpath sha256sum \
      openssl dbus-daemon busctl secret-tool gnome-keyring-daemon systemctl; do
    command -v "$command_name" >/dev/null 2>&1 || die "missing command: $command_name"
  done
  [[ -r /etc/firejail/firejail.users ]] || die "install /etc/firejail/firejail.users before staging"
  grep -Fxq "$(id -un)" /etc/firejail/firejail.users || die "current user is absent from firejail.users"
  original_codex=$(command -v codex) || die "Codex is missing"
  original_codex=$(realpath -e -- "$original_codex") || die "cannot resolve Codex"
  [[ -x "$original_codex" && "$original_codex" != "$HOME/.local/bin/codex-safe" ]] || die "cannot preserve original Codex executable"
  [[ -x "$HOME/.local/share/codex-safe/cloakbrowser-source-v0.4.11/bin/cloakserve" ]] || die "verified official cloakserve source is not installed"
  [[ -x "$HOME/.cloakbrowser/chromium-146.0.7680.177.5/chrome" ]] || die "verified CloakBrowser Chromium 146.0.7680.177.5 is missing"
  [[ $(sha256sum "$HOME/.local/share/codex-safe/cloakbrowser-source-v0.4.11/bin/cloakserve" | awk '{print $1}') == a334ec5aaf2221e8a463a7c64cfa9b290e62348582da7e03e24f927b285df1fa ]] || die "cloakserve source checksum mismatch"
  [[ $(sha256sum "$HOME/.cloakbrowser/chromium-146.0.7680.177.5/chrome" | awk '{print $1}') == 715722e8605ae3ce81523c1218aba1ec89425786ab33ceaf99f8a6cb5e70e6e8 ]] || die "CloakBrowser binary checksum mismatch"
  [[ -x "$HOME/.local/share/codex-safe/playwright-cli/node_modules/.bin/playwright-cli" ]] || die "official Playwright CLI is missing"
  [[ -x "$HOME/.local/share/codex-safe/playwright-cli/node_modules/.bin/playwright-mcp" ]] || die "official Playwright MCP is missing"
  [[ -x "$HOME/.local/share/codex-safe/tools/shellcheck" ]] || die "verified standalone ShellCheck is missing"
  [[ $(sha256sum "$HOME/.local/share/codex-safe/tools/shellcheck" | awk '{print $1}') == 4da528ddb3a4d1b7b24a59d4e16eb2f5fd960f4bd9a3708a15baddbdf1d5a55b ]] || die "standalone ShellCheck checksum mismatch"

  ephemeral_mount="$HOME/.cache/codex-safe-runtime"
  if [[ ! -e "$ephemeral_mount" && ! -L "$ephemeral_mount" ]]; then
    backup_target "$ephemeral_mount"
    install -d -m 700 "$ephemeral_mount"
  else
    [[ -d "$ephemeral_mount" && ! -L "$ephemeral_mount" ]] || die "unsafe ephemeral mountpoint already exists"
    awk -F '\t' -v target="$ephemeral_mount" '$1=="CREATED" && $2==target {found=1} END {exit !found}' "$manifest" || die "refusing unrecorded pre-existing ephemeral mountpoint"
    [[ -z $(find "$ephemeral_mount" -mindepth 1 -print -quit 2>/dev/null) ]] || die "ephemeral mountpoint is not empty"
    chmod 700 "$ephemeral_mount"
  fi

  keyring_runtime="$HOME/.cache/codex-safe-keyring-runtime"
  keyring_state="$HOME/.local/share/codex-safe/keyring"
  keyring_password="$keyring_state/unlock.key"
  for managed_dir in "$keyring_runtime" "$keyring_state"; do
    if [[ ! -e "$managed_dir" && ! -L "$managed_dir" ]]; then
      backup_target "$managed_dir"
      install -d -m 700 "$managed_dir"
    else
      [[ -d "$managed_dir" && ! -L "$managed_dir" ]] || die "unsafe managed directory: $managed_dir"
      [[ $(stat -Lc '%u' -- "$managed_dir") == "$(id -u)" ]] || die "wrong owner on $managed_dir"
      managed_mode=$(stat -Lc '%a' -- "$managed_dir")
      (( (8#$managed_mode & 8#077) == 0 )) || die "group/world-accessible managed directory: $managed_dir"
      chmod 700 "$managed_dir"
    fi
  done
  install -d -m 700 "$keyring_state/home" "$keyring_state/data" "$keyring_state/config"
  if [[ ! -e "$keyring_password" && ! -L "$keyring_password" ]]; then
    backup_target "$keyring_password"
    openssl rand -out "$keyring_password" -base64 48
    chmod 600 "$keyring_password"
  else
    [[ -f "$keyring_password" && ! -L "$keyring_password" ]] || die "unsafe private keyring unlock file"
    [[ $(stat -Lc '%u' -- "$keyring_password") == "$(id -u)" ]] || die "wrong owner on private keyring unlock file"
    [[ $(stat -Lc '%a' -- "$keyring_password") == 600 ]] || die "unsafe mode on private keyring unlock file"
  fi

  # The package ships a globally enabled user socket. Mask it for this account
  # so KDE's ksecretd remains the desktop Secret Service; codex-safe invokes the
  # daemon binary directly on a private bus and is unaffected by these masks.
  for keyring_unit in gnome-keyring-daemon.socket gnome-keyring-daemon.service; do
    mask_path="$HOME/.config/systemd/user/$keyring_unit"
    if [[ ! -L "$mask_path" || $(readlink -- "$mask_path" 2>/dev/null || true) != /dev/null ]]; then
      backup_target "$mask_path"
    fi
  done
  systemctl --user mask --now gnome-keyring-daemon.socket gnome-keyring-daemon.service >/dev/null

  install -d -m 700 "$HOME/.config/codex-safe" "$HOME/.config/codex-safe/python" "$HOME/.config/firejail"
  install -d -m 755 "$HOME/.local/bin" "$HOME/.local/share/codex-safe"
  install_payload_file .config/firejail/codex-safe.profile 644
  install_payload_file .config/codex-safe/config 600
  install_payload_file .config/codex-safe/keyring-stack.sh 600
  install_payload_file .config/codex-safe/runtime-inner.sh 755
  install_payload_file .config/codex-safe/self-test-inner.sh 755
  install_payload_file .config/codex-safe/node-playwright-preload.cjs 644
  install_payload_file .config/codex-safe/python/sitecustomize.py 644
  install_payload_file .config/codex-safe/intentionally-invalid.profile 600
  install_payload_file .config/codex-safe/README.md 644
  install_payload_file .config/codex-safe/PROVENANCE.md 644
  install_payload_file .config/codex-safe/doctor.sh 755
  install_payload_file .config/codex-safe/test-sandbox.sh 755
  install_payload_file .config/codex-safe/uninstall.sh 755
  install_payload_file .local/bin/codex-safe 755
  install_payload_file .local/bin/codex-safe-migrate-mcp 755
  install_payload_file .local/bin/cloakserve 755
  install_payload_file .local/bin/playwright-cli 755
  install_payload_file .local/bin/playwright-mcp-safe 755

  original_link="$HOME/.config/codex-safe/codex-original"
  if [[ ! -L "$original_link" || $(readlink -f "$original_link" 2>/dev/null || true) != "$original_codex" ]]; then
    backup_target "$original_link"
    ln -sfn "$original_codex" "$original_link"
  fi
  printf 'installed_at=%s\noriginal_codex=%s\n' "$timestamp" "$original_codex" >"$HOME/.config/codex-safe/install-state"
  chmod 600 "$HOME/.config/codex-safe/install-state"
  note "staged hardened runtime; shell alias and global browser instructions are not yet changed"
  exit 0
fi

agents_begin='<!-- codex-safe browser policy: begin -->'
agents_end='<!-- codex-safe browser policy: end -->'
# This policy block is deliberately literal; its backticks are Markdown, not
# shell substitutions.
# shellcheck disable=SC2016
agents_content='## Hardened browser policy

Use CloakBrowser-backed Playwright whenever a task requires opening, rendering, interacting with, screenshotting, extracting from, scraping, dynamically inspecting, or visually validating a webpage. Use the `playwright-cli` wrapper or the `playwright_safe` MCP server supplied by `codex-safe`; both attach to the session `CLOAK_CDP_ENDPOINT`.

Search APIs may be used only to discover sources and URLs. Do not claim that built-in search traffic itself passes through CloakBrowser. Do not fall back silently to stock Chromium. If CloakBrowser or its CDP endpoint is unavailable, report the failure.

Do not use CloakBrowser stealth functionality to bypass authentication, CAPTCHA, paywalls, access controls, rate limits, robots directives, or legal restrictions.'
append_block "$HOME/.codex/AGENTS.md" "$agents_begin" "$agents_end" "$agents_content"

note "browser policy integration installed"
