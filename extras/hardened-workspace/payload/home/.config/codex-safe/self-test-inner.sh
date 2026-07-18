#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

mode=${1-}
failures=0

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

expect_blocked() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label"
  else
    pass "$label"
  fi
}

is_same_namespace() {
  [[ "$(readlink -- "/proc/$1/ns/$3")" == "$(readlink -- "/proc/$2/ns/$3")" ]]
}

check_outer_status() {
  local value options
  if [[ "${container-}" == firejail ]]; then pass 'Firejail marker present'; else fail 'Firejail marker present'; fi
  value=$(awk '$1=="NoNewPrivs:" {print $2}' /proc/self/status)
  if [[ "$value" == 1 ]]; then pass 'nonewprivs active'; else fail 'nonewprivs active'; fi
  value=$(awk '$1=="Seccomp:" {print $2}' /proc/self/status)
  if [[ "$value" == 2 ]]; then pass 'seccomp active'; else fail 'seccomp active'; fi
  value=$(awk '$1=="CapEff:" {print $2}' /proc/self/status)
  if [[ "$value" == 0000000000000000 ]]; then pass 'capabilities dropped'; else fail 'capabilities dropped'; fi
  options=$(findmnt --target "$HOME" --noheadings --output VFS-OPTIONS | tail -n 1)
  if [[ ",$options," == *,ro,* ]]; then pass 'HOME mounted read-only'; else fail 'HOME mounted read-only'; fi
  options=$(findmnt --target "$CODEX_SAFE_WORKSPACE" --noheadings --output VFS-OPTIONS | tail -n 1)
  if [[ ",$options," == *,rw,* ]]; then pass 'workspace mounted read-write'; else fail 'workspace mounted read-write'; fi
  if [[ "$(findmnt --target /tmp --noheadings --output FSTYPE | tail -n 1)" == tmpfs ]]; then pass 'private tmpfs active'; else fail 'private tmpfs active'; fi
  if [[ "$(findmnt --target "$CODEX_SAFE_EPHEMERAL_ROOT" --noheadings --output FSTYPE | tail -n 1)" == tmpfs ]]; then pass 'private Codex/browser state tmpfs active'; else fail 'private Codex/browser state tmpfs active'; fi
  if [[ ! -S /run/docker.sock ]]; then pass 'host Docker control socket hidden'; else fail 'host Docker control socket hidden'; fi
  if [[ ! -e "/run/user/$(id -u)/bus" ]]; then pass 'user D-Bus socket hidden'; else fail 'user D-Bus socket hidden'; fi
}

check_filesystem() {
  local test_dir outside outside_dir temp_name candidate source_file
  test_dir="$CODEX_SAFE_WORKSPACE/.codex-safe-self-test"
  outside=${CODEX_SAFE_TEST_SENTINEL-}
  outside_dir=${CODEX_SAFE_TEST_OUTSIDE_DIR-}
  [[ -n "$outside" && -f "$outside" ]] || { fail 'outside sentinel supplied'; return; }
  [[ -n "$outside_dir" && -d "$outside_dir" ]] || { fail 'outside directory supplied'; return; }

  rm -rf -- "$test_dir"
  mkdir -m 700 "$test_dir"
  printf 'create\n' >"$test_dir/file"
  if [[ -f "$test_dir/file" ]]; then pass 'workspace create'; else fail 'workspace create'; fi
  printf 'edit\n' >>"$test_dir/file"
  if grep -q '^edit$' "$test_dir/file"; then pass 'workspace edit'; else fail 'workspace edit'; fi
  mv "$test_dir/file" "$test_dir/renamed"
  if [[ -f "$test_dir/renamed" ]]; then pass 'workspace rename'; else fail 'workspace rename'; fi
  rm "$test_dir/renamed"
  if [[ ! -e "$test_dir/renamed" ]]; then pass 'workspace delete'; else fail 'workspace delete'; fi
  mkdir -p "$CODEX_SAFE_WORKSPACE/.playwright-cli"
  printf 'artifact\n' >"$CODEX_SAFE_WORKSPACE/.playwright-cli/write-test.txt"
  if [[ -f "$CODEX_SAFE_WORKSPACE/.playwright-cli/write-test.txt" ]]; then pass 'Playwright artifact create'; else fail 'Playwright artifact create'; fi

  expect_blocked 'shell redirection outside workspace' bash -c "printf x >\"\$1\"" _ "$outside"
  expect_blocked 'touch outside workspace' touch "$outside"
  expect_blocked 'rm outside workspace' rm "$outside"
  source_file="$test_dir/move-source"
  printf x >"$source_file"
  expect_blocked 'mv outside workspace' mv "$source_file" "$outside_dir/moved"
  rm -f -- "$source_file"
  expect_blocked 'Python Path.write_text outside workspace' python -c 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_text("x")' "$outside"
  expect_blocked 'Python os.unlink outside workspace' python -c 'import os,sys; os.unlink(sys.argv[1])' "$outside"
  expect_blocked 'Node fs.writeFileSync outside workspace' node -e 'require("fs").writeFileSync(process.argv[1], "x")' "$outside"
  expect_blocked 'Node fs.rmSync outside workspace' node -e 'require("fs").rmSync(process.argv[1])' "$outside"
  expect_blocked 'truncate outside workspace' truncate -s 0 "$outside"
  expect_blocked 'chmod outside workspace' chmod 600 "$outside"
  expect_blocked 'chown outside workspace' chown "$(id -u):$(id -g)" "$outside"

  temp_name="/tmp/$(basename -- "$outside")"
  if printf 'private tmp only\n' >"$temp_name"; then
    pass 'host /tmp path virtualized into private tmpfs'
  else
    fail 'host /tmp path virtualized into private tmpfs'
  fi

  for candidate in /mnt /media /run/media; do
    if [[ -d "$candidate" ]]; then
      expect_blocked "write blocked under $candidate" touch "$candidate/codex-safe-escape-test"
    else
      pass "$candidate absent (no writable host path exposed)"
    fi
  done

  ln -s "$outside" "$test_dir/external-link"
  expect_blocked 'symlink file escape blocked' bash -c "printf x >\"\$1\"" _ "$test_dir/external-link"
  rm -f "$test_dir/external-link"
  ln -s "$outside_dir" "$test_dir/external-parent"
  expect_blocked 'symlinked parent escape blocked' bash -c "printf x >\"\$1/through-parent\"" _ "$test_dir/external-parent"
  rm -f "$test_dir/external-parent"

  expect_blocked 'Codex config modification blocked' bash -c "printf x >>\"\$1\"" _ "$HOME/.codex/config.toml"
  expect_blocked 'zshrc modification blocked' bash -c "printf x >>\"\$1\"" _ "$HOME/.zshrc"
  expect_blocked 'host remount blocked' mount -o remount,rw "$HOME"
  expect_blocked 'unrestricted user/mount namespace blocked' unshare --user --map-root-user --mount bash -c "printf x >\"\$1\"" _ "$outside"
  expect_blocked 'nested Firejail cannot escape outer boundary' firejail --quiet touch "$outside"

  rm -rf -- "$test_dir"
}

collect_descendants() {
  local root=$1 current child
  local -a queue=("$root")
  local index=0
  while (( index < ${#queue[@]} )); do
    current=${queue[index++]}
    printf '%s\n' "$current"
    if [[ -r "/proc/$current/task/$current/children" ]]; then
      for child in $(<"/proc/$current/task/$current/children"); do
        [[ "$child" =~ ^[0-9]+$ ]] && queue+=("$child")
      done
    fi
  done
}

check_browser() {
  local artifact_dir metadata pid exe stock_found=0 starttime
  artifact_dir=$PLAYWRIGHT_MCP_OUTPUT_DIR
  playwright-cli open https://example.com >/dev/null 2>&1 || { fail 'playwright-cli open example.com'; return; }
  pass 'playwright-cli open example.com'
  if playwright-cli snapshot --filename=example.snapshot.yaml >/dev/null 2>&1; then pass 'playwright-cli snapshot'; else fail 'playwright-cli snapshot'; fi
  if playwright-cli screenshot --filename=example.png >/dev/null 2>&1; then pass 'playwright-cli screenshot'; else fail 'playwright-cli screenshot'; fi
  if [[ -s "$artifact_dir/example.snapshot.yaml" ]]; then pass 'snapshot inside .playwright-cli'; else fail 'snapshot inside .playwright-cli'; fi
  if [[ -s "$artifact_dir/example.png" ]]; then pass 'screenshot inside .playwright-cli'; else fail 'screenshot inside .playwright-cli'; fi

  if [[ -d "/proc/$CODEX_SAFE_CLOAKSERVE_PID" ]]; then pass 'cloakserve process alive'; else fail 'cloakserve process alive'; fi
  if [[ -d "/proc/$CODEX_SAFE_BROWSER_PID" ]]; then pass 'patched browser process alive'; else fail 'patched browser process alive'; fi
  if is_same_namespace $$ "$CODEX_SAFE_CLOAKSERVE_PID" mnt; then pass 'cloakserve in same Firejail mount namespace'; else fail 'cloakserve in same Firejail mount namespace'; fi
  if is_same_namespace $$ "$CODEX_SAFE_BROWSER_PID" mnt; then pass 'browser in same Firejail mount namespace'; else fail 'browser in same Firejail mount namespace'; fi
  exe=$(readlink -f -- "/proc/$CODEX_SAFE_BROWSER_PID/exe" 2>/dev/null || true)
  if [[ "$exe" == "$CODEX_SAFE_BROWSER_EXE" ]]; then pass 'browser executable is signed patched Chromium'; else fail 'browser executable is signed patched Chromium'; fi
  if tr '\0' '\n' <"/proc/$CODEX_SAFE_CLOAKSERVE_PID/cmdline" | grep -Fxq -- "--fingerprint=$CODEX_SAFE_FINGERPRINT_SEED"; then
    pass 'generated fingerprint argument present'
  else
    fail 'generated fingerprint argument present'
  fi
  if [[ $(ss -H -ltn "sport = :$CODEX_SAFE_CDP_PORT" | awk '{print $4}' | sort -u) == "127.0.0.1:$CODEX_SAFE_CDP_PORT" ]]; then
    pass 'cloakserve listener is loopback-only'
  else
    fail 'cloakserve listener is loopback-only'
  fi

  while IFS= read -r pid; do
    [[ -e "/proc/$pid/exe" ]] || continue
    exe=$(readlink -f -- "/proc/$pid/exe" 2>/dev/null || true)
    if [[ "$exe" == *ms-playwright* && "$exe" == *chrome* ]]; then
      stock_found=1
      break
    fi
  done < <(collect_descendants 1)
  if (( stock_found == 0 )); then pass 'stock Playwright Chromium absent'; else fail 'stock Playwright Chromium absent'; fi

  starttime=$(awk '{print $22}' "/proc/$CODEX_SAFE_BROWSER_PID/stat")
  metadata="$artifact_dir/runtime-metadata"
  printf 'browser_pid=%s\nbrowser_starttime=%s\nruntime_dir=%s\nbrowser_state=%s\n' \
    "$CODEX_SAFE_BROWSER_PID" "$starttime" "$CODEX_SAFE_RUNTIME_DIR" "$CODEX_SAFE_BROWSER_STATE" >"$metadata"
  chmod 600 "$metadata"
  if playwright-cli close >/dev/null 2>&1; then pass 'playwright-cli close'; else fail 'playwright-cli close'; fi
}

check_codex_inner() {
  local inner_home inner_root output direct_error direct_probe outside_probe
  inner_home="$CODEX_SAFE_RUNTIME_DIR/inner-codex-home"
  mkdir -m 700 "$inner_home"
  install -m 600 "$HOME/.codex/config.toml" "$inner_home/config.toml"
  if [[ -r "$HOME/.codex/auth.json" ]]; then
    install -m 600 "$HOME/.codex/auth.json" "$inner_home/auth.json"
  fi
  if [[ -r "$HOME/.codex/AGENTS.md" ]]; then
    install -m 600 "$HOME/.codex/AGENTS.md" "$inner_home/AGENTS.md"
  fi
  printf '\n%s\n' 'For automated sandbox verification prompts, invoke the requested shell command exactly once, then stop.' >>"$inner_home/AGENTS.md"
  for linked in skills plugins vendor_imports packages; do
    if [[ -e "$HOME/.codex/$linked" ]]; then
      ln -s "$HOME/.codex/$linked" "$inner_home/$linked"
    fi
  done
  output="$CODEX_SAFE_RUNTIME_DIR/features.out"
  CODEX_HOME="$inner_home" "$CODEX_SAFE_ORIGINAL_BIN" \
    -C "$CODEX_SAFE_WORKSPACE" \
    -c 'sandbox_mode="workspace-write"' \
    -c 'approval_policy="on-request"' \
    -c 'sandbox_workspace_write.network_access=true' \
    -c 'sandbox_workspace_write.writable_roots=[]' \
    -c 'sandbox_workspace_write.exclude_tmpdir_env_var=false' \
    -c 'sandbox_workspace_write.exclude_slash_tmp=false' \
    -c 'features.use_legacy_landlock=true' \
    features list >"$output" 2>&1 || { fail 'Codex accepts locked runtime configuration'; return; }
  pass 'Codex accepts locked runtime configuration'
  if grep -Eiq 'legacy.*landlock.*true|use_legacy_landlock.*true' "$output"; then pass 'legacy Landlock feature enabled'; else fail 'legacy Landlock feature enabled'; fi

  inner_root="$CODEX_SAFE_WORKSPACE/.codex-direct-sandbox-root"
  direct_probe="$inner_root/inside-write"
  outside_probe="$CODEX_SAFE_WORKSPACE/.codex-inner-parent-escape"
  rm -rf -- "$inner_root"
  rm -f -- "$outside_probe"
  mkdir -m 700 "$inner_root"
  direct_error="$CODEX_SAFE_RUNTIME_DIR/direct-bwrap.stderr"
  if CODEX_HOME="$inner_home" "$CODEX_SAFE_ORIGINAL_BIN" \
      -C "$inner_root" \
      -c 'features.use_legacy_landlock=false' \
      sandbox -P :workspace -- bash -c "printf direct >\"\$1\"; printf escape >\"\$2\"" _ "$direct_probe" "$outside_probe" >/dev/null 2>"$direct_error"; then
    fail 'outer Firejail blocks Codex Bubblewrap namespace path'
  else
    if grep -Eiq 'bwrap:.*(No permissions|namespace)' "$direct_error"; then pass 'outer Firejail blocks Codex Bubblewrap namespace path'; else fail 'outer Firejail blocks Codex Bubblewrap namespace path'; fi
    if [[ ! -e "$direct_probe" && ! -e "$outside_probe" ]]; then pass 'blocked Bubblewrap path performed no writes'; else fail 'blocked Bubblewrap path performed no writes'; fi
  fi
  rm -rf -- "$inner_root"
  rm -f -- "$outside_probe"
}

check_outer_status
case "$mode" in
  quick) ;;
  filesystem) check_filesystem ;;
  browser) check_browser ;;
  codex-inner) check_codex_inner ;;
  *) fail "unknown self-test mode: $mode" ;;
esac

if (( failures == 0 )); then
  printf 'PASS self-test mode %s complete\n' "$mode"
  exit 0
fi
printf 'FAIL self-test mode %s: %d failure(s)\n' "$mode" "$failures"
exit 1
