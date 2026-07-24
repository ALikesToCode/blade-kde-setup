#!/usr/bin/env bash
# Host-side end-to-end verifier. Run from a normal standalone repository parent,
# not from HOME or a mount root. Every sandbox probe enters via codex-safe.
set -Eeuo pipefail
umask 077

failures=0
test_root=''
outside_dir=''
host_tmp_sentinel=''

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  set +e
  [[ -z "$outside_dir" || ! -d "$outside_dir" ]] || rm -rf -- "$outside_dir"
  [[ -z "$host_tmp_sentinel" || ! -e "$host_tmp_sentinel" ]] || rm -f -- "$host_tmp_sentinel"
  if [[ "${CODEX_SAFE_KEEP_TEST_REPO-0}" != 1 && -n "$test_root" && "$test_root" == "$PWD/.codex-safe-verification."* ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

run_expect_success() {
  local label=$1
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

run_expect_failure() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then fail "$label"; else pass "$label"; fi
}

launcher="$HOME/.local/bin/codex-safe"
config_dir="$HOME/.config/codex-safe"
shellcheck_real="$HOME/.local/share/codex-safe/tools/shellcheck"
[[ -x "$launcher" ]] || { fail 'codex-safe installed'; exit 1; }

test_root=$(mktemp -d "$PWD/.codex-safe-verification.XXXXXXXX")
chmod 700 "$test_root"
git -C "$test_root" init -q
printf 'verification repository\n' >"$test_root/README.txt"
git -C "$test_root" add README.txt
git -C "$test_root" -c user.name=codex-safe-test -c user.email=codex-safe-test@invalid commit -qm 'verification fixture'
outside_dir=$(mktemp -d "$HOME/.codex-safe-outside.XXXXXXXX")
chmod 700 "$outside_dir"
outside_sentinel="$outside_dir/sentinel"
printf 'outside-sentinel-%s\n' "$(date +%s%N)" >"$outside_sentinel"
chmod 640 "$outside_sentinel"
outside_hash=$(sha256sum "$outside_sentinel" | awk '{print $1}')
outside_stat=$(stat -Lc '%a:%u:%g:%s' "$outside_sentinel")
host_tmp_sentinel="/tmp/$(basename -- "$outside_sentinel")"
printf 'host-tmp-sentinel-%s\n' "$(date +%s%N)" >"$host_tmp_sentinel"
chmod 640 "$host_tmp_sentinel"
tmp_hash=$(sha256sum "$host_tmp_sentinel" | awk '{print $1}')
tmp_stat=$(stat -Lc '%a:%u:%g:%s' "$host_tmp_sentinel")

printf 'Verification repository: %s\n' "$test_root"

for script in \
  "$HOME/.local/bin/codex-safe" \
  "$HOME/.local/bin/codex-safe-migrate-mcp" \
  "$HOME/.local/bin/cloakserve" \
  "$HOME/.local/bin/playwright-cli" \
  "$HOME/.local/bin/playwright-mcp-safe" \
  "$config_dir/runtime-inner.sh" \
  "$config_dir/keyring-stack.sh" \
  "$config_dir/self-test-inner.sh" \
  "$config_dir/doctor.sh" \
  "$config_dir/test-sandbox.sh" \
  "$config_dir/uninstall.sh"; do
  if bash -n "$script"; then pass "bash -n $script"; else fail "bash -n $script"; fi
  if [[ -x "$shellcheck_real" ]]; then
    if "$shellcheck_real" -x "$script"; then pass "shellcheck $script"; else fail "shellcheck $script"; fi
  else
    fail "shellcheck unavailable for $script"
  fi
done
if node --check "$config_dir/node-playwright-preload.cjs"; then pass 'Node preload syntax'; else fail 'Node preload syntax'; fi
pycache="$test_root/pycache"
if PYTHONPYCACHEPREFIX="$pycache" python -m py_compile "$config_dir/python/sitecustomize.py"; then pass 'Python sitecustomize syntax'; else fail 'Python sitecustomize syntax'; fi
rm -rf "$pycache"

uninstall_home="$test_root/uninstall-home"
mkdir -p "$uninstall_home/.codex" "$uninstall_home/.config/codex-safe/backups" "$uninstall_home/.cache/codex-safe-runtime"
printf '%s\n\n%s\n%s\n%s\n' 'keep-agents-content' '<!-- codex-safe browser policy: begin -->' 'temporary browser policy' '<!-- codex-safe browser policy: end -->' >"$uninstall_home/.codex/AGENTS.md"
printf '%s\n%s\n%s\n' '# >>> codex-safe alias >>>' "alias codex='codex-safe'" '# <<< codex-safe alias <<<' >"$uninstall_home/.zshrc"
printf 'CREATED\t%s\t-\nCREATED\t%s\t-\n' "$uninstall_home/.zshrc" "$uninstall_home/.cache/codex-safe-runtime" >"$uninstall_home/.config/codex-safe/backups/manifest.tsv"
if HOME="$uninstall_home" "$config_dir/uninstall.sh" >/dev/null && \
    grep -Fxq 'keep-agents-content' "$uninstall_home/.codex/AGENTS.md" && \
    ! rg -q 'codex-safe browser policy' "$uninstall_home/.codex/AGENTS.md" && \
    [[ ! -e "$uninstall_home/.zshrc" ]]; then
  pass 'uninstall simulation preserves unrelated content and reverses created zshrc'
else
  fail 'uninstall simulation preserves unrelated content and reverses created zshrc'
fi

run_expect_failure 'reject --yolo' "$launcher" --yolo --version
run_expect_failure 'reject dangerously-bypass flag' "$launcher" --dangerously-bypass-approvals-and-sandbox --version
run_expect_failure 'reject --add-dir' "$launcher" --add-dir "$HOME" --version
run_expect_failure 'reject -C /' "$launcher" -C / --version
run_expect_failure 'reject --cd HOME' "$launcher" --cd "$HOME" --version
run_expect_failure 'reject sandbox override' "$launcher" --sandbox danger-full-access --version
run_expect_failure 'reject approval override' "$launcher" --ask-for-approval never --version
run_expect_failure 'reject locked config override' "$launcher" -c 'sandbox_workspace_write.writable_roots=["/home"]' --version
run_expect_failure 'reject attached sandbox override' "$launcher" -sdanger-full-access --version
run_expect_failure 'reject attached approval override' "$launcher" -anever --version
run_expect_failure 'reject attached locked config override' "$launcher" '-csandbox_mode="danger-full-access"' --version
run_expect_failure 'reject attached profile override' "$launcher" -punsafe --version

original_pwd=$PWD
cd "$test_root"
printf 'hard-link-risk\n' >hardlink-source
ln hardlink-source hardlink-alias
run_expect_success 'allow hard links when every inode alias is internal' "$launcher" --version
rm -f hardlink-source hardlink-alias
printf 'external-hard-link-risk\n' >"$outside_dir/hardlink-source"
ln "$outside_dir/hardlink-source" hardlink-external-alias
run_expect_failure 'refuse hard links with an external inode alias' "$launcher" --version
rm -f hardlink-external-alias "$outside_dir/hardlink-source"
run_expect_failure 'fail closed when CloakBrowser unavailable' env CODEX_SAFE_SIMULATE_CLOAK_MISSING=1 "$launcher" --version
run_expect_failure 'fail closed on invalid Firejail profile' env CODEX_SAFE_SIMULATE_INVALID_PROFILE=1 "$launcher" --version
run_expect_failure 'fail closed on simulated rejected Firejail user' env CODEX_SAFE_SIMULATE_FIREJAIL_DENY=1 "$launcher" --version
run_expect_success 'live quick sandbox test' "$launcher" --codex-safe-self-test quick
run_expect_success 'filesystem security suite' env CODEX_SAFE_TEST_SENTINEL="$outside_sentinel" CODEX_SAFE_TEST_OUTSIDE_DIR="$outside_dir" "$launcher" --codex-safe-self-test filesystem
run_expect_success 'Codex inner Landlock suite' "$launcher" --codex-safe-self-test codex-inner
run_expect_success 'CloakBrowser and Playwright suite' "$launcher" --codex-safe-self-test browser
cd "$original_pwd"

git -C "$test_root" worktree add -q -b codex-safe-linked-worktree "$test_root/linked-worktree"
if ( cd "$test_root/linked-worktree" && "$launcher" --codex-safe-self-test quick >worktree-detection.log 2>&1 ) && \
    grep -Fq 'Git worktree gitdir is outside the writable boundary' "$test_root/linked-worktree/worktree-detection.log"; then
  pass 'external Git worktree gitdir detected and kept outside writable root'
else
  fail 'external Git worktree gitdir detected and kept outside writable root'
fi

new_outside_hash=$(sha256sum "$outside_sentinel" | awk '{print $1}')
new_outside_stat=$(stat -Lc '%a:%u:%g:%s' "$outside_sentinel")
if [[ "$new_outside_hash" == "$outside_hash" && "$new_outside_stat" == "$outside_stat" ]]; then pass 'outside sentinel byte-for-byte and metadata unchanged'; else fail 'outside sentinel byte-for-byte and metadata unchanged'; fi
new_tmp_hash=$(sha256sum "$host_tmp_sentinel" | awk '{print $1}')
new_tmp_stat=$(stat -Lc '%a:%u:%g:%s' "$host_tmp_sentinel")
if [[ "$new_tmp_hash" == "$tmp_hash" && "$new_tmp_stat" == "$tmp_stat" ]]; then pass 'real host /tmp sentinel unchanged'; else fail 'real host /tmp sentinel unchanged'; fi
if [[ ! -e "$outside_dir/moved" && ! -e "$outside_dir/through-parent" ]]; then pass 'no outside escape files created'; else fail 'no outside escape files created'; fi
if [[ -d "$HOME/.cache/codex-safe-runtime" ]] && [[ -z $(find "$HOME/.cache/codex-safe-runtime" -mindepth 1 -print -quit 2>/dev/null) ]]; then pass 'host ephemeral state mountpoint remains empty'; else fail 'host ephemeral state mountpoint remains empty'; fi

metadata="$test_root/.playwright-cli/runtime-metadata"
if [[ -r "$metadata" ]]; then
  browser_pid=$(awk -F= '$1=="browser_pid" {print $2}' "$metadata")
  browser_starttime=$(awk -F= '$1=="browser_starttime" {print $2}' "$metadata")
  runtime_dir=$(awk -F= '$1=="runtime_dir" {print substr($0,index($0,"=")+1)}' "$metadata")
  browser_state=$(awk -F= '$1=="browser_state" {print substr($0,index($0,"=")+1)}' "$metadata")
  if [[ -r "/proc/$browser_pid/stat" ]] && [[ $(awk '{print $22}' "/proc/$browser_pid/stat") == "$browser_starttime" ]]; then fail 'browser process terminated after session'; else pass 'browser process terminated after session'; fi
  if [[ ! -e "$runtime_dir" ]]; then pass 'private runtime state disappeared'; else fail 'private runtime state disappeared'; fi
  if [[ ! -e "$browser_state" ]]; then pass 'browser profile state disappeared'; else fail 'browser profile state disappeared'; fi
else
  fail 'browser runtime metadata created'
fi

backup_manifest="$config_dir/backups/manifest.tsv"
if [[ -r "$backup_manifest" ]]; then
  backup_failure=0
  while IFS=$'\t' read -r kind _original backup; do
    [[ "$kind" == BACKUP ]] || continue
    [[ -e "$backup" ]] || backup_failure=1
  done <"$backup_manifest"
  if (( backup_failure == 0 )); then pass 'backups exist for every recorded pre-existing file'; else fail 'backups exist for every recorded pre-existing file'; fi
else
  fail 'backup manifest exists'
fi

if "$config_dir/doctor.sh"; then pass 'doctor static checks'; else fail 'doctor static checks'; fi

printf 'Verification repository retained: %s\n' "$test_root"
if (( failures == 0 )); then
  printf 'PASS full verification suite complete\n'
  exit 0
fi
printf 'FAIL full verification suite: %d failure(s)\n' "$failures"
exit 1
