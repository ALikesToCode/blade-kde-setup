#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bridge="$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/clipboard-bridge.py"
test_root=$(mktemp -d)
bridge_pid=''

cleanup() {
  set +e
  if [[ -n "$bridge_pid" ]] && kill -0 "$bridge_pid" 2>/dev/null; then
    kill -TERM "$bridge_pid"
    wait "$bridge_pid"
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fake_xclip="$test_root/xclip"
capture="$test_root/nested-clipboard"
ready="$test_root/ready"
log="$test_root/bridge.log"

cat >"$fake_xclip" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${DISPLAY-}" == :41 ]]; then
  printf '%s' 'synthetic-paste-value'
  exit 0
fi
if [[ "${DISPLAY-}" == :42 ]]; then
  value=$(</dev/stdin)
  printf '%s' "$value" >"$TEST_CAPTURE"
  trap 'exit 0' TERM INT
  while :; do sleep 1; done
fi
exit 1
EOF
chmod 700 "$fake_xclip"

TEST_CAPTURE="$capture" \
  python -I -S "$bridge" \
    --host-display :41 \
    --host-authority "$test_root/host.Xauthority" \
    --nested-display :42 \
    --nested-authority "$test_root/nested.Xauthority" \
    --xclip "$fake_xclip" \
    --ready-file "$ready" >"$log" 2>&1 &
bridge_pid=$!

deadline=$((SECONDS + 5))
while (( SECONDS < deadline )); do
  [[ -f "$ready" && -f "$capture" ]] && break
  kill -0 "$bridge_pid" 2>/dev/null || {
    printf 'Clipboard bridge exited during its synthetic test.\n' >&2
    exit 1
  }
  sleep 0.05
done

[[ -f "$ready" ]]
[[ $(<"$capture") == synthetic-paste-value ]]
[[ ! -s "$log" ]]

kill -TERM "$bridge_pid"
wait "$bridge_pid"
bridge_pid=''

if pgrep -f -- "$fake_xclip" >/dev/null 2>&1; then
  printf 'Clipboard owner remained alive after bridge shutdown.\n' >&2
  exit 1
fi

printf 'Clipboard bridge tests passed.\n'
