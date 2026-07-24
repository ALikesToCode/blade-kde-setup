#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

purge=0
[[ "${1-}" != --purge ]] || purge=1
if [[ $# -gt 1 || ( $# -eq 1 && "${1-}" != --purge ) ]]; then
  printf 'usage: %s [--purge]\n' "$0" >&2
  exit 2
fi

remove_marked_block() {
  local target=$1 begin=$2 end=$3 temp
  [[ -f "$target" ]] || return 0
  temp=$(mktemp "$(dirname -- "$target")/.codex-safe-uninstall.XXXXXXXX")
  awk -v begin="$begin" -v end="$end" '
    $0==begin {
      if (have && previous != "") print previous
      have=0
      skip=1
      next
    }
    $0==end {skip=0; next}
    skip {next}
    {if (have) print previous; previous=$0; have=1}
    END {if (have) print previous}
  ' "$target" >"$temp"
  chmod --reference="$target" "$temp"
  mv -f -- "$temp" "$target"
}

printf '%s\n' 'codex-safe uninstall: removing only marked integration and recorded payload files.'
remove_marked_block "$HOME/.codex/AGENTS.md" '<!-- codex-safe browser policy: begin -->' '<!-- codex-safe browser policy: end -->'
remove_marked_block "$HOME/.zshrc" '# >>> codex-safe alias >>>' '# <<< codex-safe alias <<<'

manifest="$HOME/.config/codex-safe/backups/manifest.tsv"
declare -A restored=()
if [[ -r "$manifest" ]]; then
  while IFS=$'\t' read -r kind original backup; do
    [[ "$kind" == BACKUP ]] || continue
    [[ -n "${restored[$original]-}" ]] && continue
    # These files are integration surfaces that users may edit after install.
    # The marked blocks were removed above; restoring a whole old backup would
    # discard unrelated later changes.
    case "$original" in
      "$HOME/.codex/AGENTS.md"|"$HOME/.zshrc") continue ;;
    esac
    if [[ -e "$backup" || -L "$backup" ]]; then
      mkdir -p "$(dirname -- "$original")"
      cp -a -- "$backup" "$original"
      restored[$original]=1
      printf 'restored %s\n' "$original"
    fi
  done <"$manifest"
fi

created=(
  "$HOME/.local/bin/codex-safe"
  "$HOME/.local/bin/codex-safe-migrate-mcp"
  "$HOME/.local/bin/cloakserve"
  "$HOME/.local/bin/playwright-cli"
  "$HOME/.local/bin/playwright-mcp-safe"
  "$HOME/.config/firejail/codex-safe.profile"
  "$HOME/.config/codex-safe/config"
  "$HOME/.config/codex-safe/keyring-stack.sh"
  "$HOME/.config/codex-safe/runtime-inner.sh"
  "$HOME/.config/codex-safe/self-test-inner.sh"
  "$HOME/.config/codex-safe/node-playwright-preload.cjs"
  "$HOME/.config/codex-safe/python/sitecustomize.py"
  "$HOME/.config/codex-safe/intentionally-invalid.profile"
  "$HOME/.config/codex-safe/README.md"
  "$HOME/.config/codex-safe/PROVENANCE.md"
  "$HOME/.config/codex-safe/doctor.sh"
  "$HOME/.config/codex-safe/test-sandbox.sh"
  "$HOME/.config/codex-safe/uninstall.sh"
  "$HOME/.config/codex-safe/codex-original"
  "$HOME/.config/codex-safe/install-state"
  "$HOME/.config/systemd/user/gnome-keyring-daemon.socket"
  "$HOME/.config/systemd/user/gnome-keyring-daemon.service"
)
for target in "${created[@]}"; do
  [[ -n "${restored[$target]-}" ]] || rm -f -- "$target"
done
systemctl --user daemon-reload >/dev/null 2>&1 || true
runtime_mount="$HOME/.cache/codex-safe-runtime"
if [[ -z "${restored[$runtime_mount]-}" ]]; then
  rmdir -- "$runtime_mount" 2>/dev/null || printf 'kept non-empty runtime mountpoint %s\n' "$runtime_mount"
fi
keyring_runtime="$HOME/.cache/codex-safe-keyring-runtime"
if [[ -z "${restored[$keyring_runtime]-}" ]]; then
  rmdir -- "$keyring_runtime" 2>/dev/null || printf 'kept non-empty keyring runtime directory %s\n' "$keyring_runtime"
fi
if awk -F '\t' -v target="$HOME/.zshrc" '$1=="CREATED" && $2==target {found=1} END {exit !found}' "$manifest" 2>/dev/null && [[ -f "$HOME/.zshrc" && ! -s "$HOME/.zshrc" ]]; then
  rm -f -- "$HOME/.zshrc"
fi

if [[ -r /etc/firejail/firejail.users ]] && grep -Fxq "$(id -un)" /etc/firejail/firejail.users; then
  printf 'System cleanup requires sudo: remove %s from /etc/firejail/firejail.users when no other codex-safe install needs it.\n' "$(id -un)"
fi

if (( purge == 1 )); then
  printf '%s\n' 'WARNING: --purge removes the private MCP keyring, CloakBrowser pipx environment, verified browser cache, and dedicated Playwright npm tree.'
  pipx uninstall cloakbrowser 2>/dev/null || true
  if [[ "$HOME/.local/share/codex-safe" == "$HOME/"* ]]; then rm -rf -- "$HOME/.local/share/codex-safe"; fi
  if [[ "$HOME/.cloakbrowser" == "$HOME/"* ]]; then rm -rf -- "$HOME/.cloakbrowser"; fi
fi

if (( purge == 0 )) && [[ -d "$HOME/.local/share/codex-safe/keyring" ]]; then
  printf 'Preserved private MCP credentials at %s\n' "$HOME/.local/share/codex-safe/keyring"
fi

printf 'Backups remain at %s\n' "$HOME/.config/codex-safe/backups"
printf 'Review them, then remove %s manually if no longer needed.\n' "$HOME/.config/codex-safe"
printf '%s\n' 'codex-safe uninstall complete.'
