#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
trap 'printf "aria2 daemon test failed at line %s\n" "$LINENO" >&2' ERR

TEST_HOME="$TEST_ROOT/home"
TEST_CONFIG="$TEST_HOME/.config"
TEST_STATE="$TEST_HOME/.local/state"
MOCK_ARIA2C="$TEST_ROOT/aria2c"
MOCK_CAPTURE="$TEST_ROOT/arguments"

mkdir -p -- "$TEST_CONFIG/aria2"
sed "s|__HOME__|$TEST_HOME|g" \
    "$ROOT/dotfiles/downloads/aria2/daemon.conf" \
    > "$TEST_CONFIG/aria2/daemon.conf"

cat > "$MOCK_ARIA2C" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_CAPTURE"
EOF
chmod 0755 -- "$MOCK_ARIA2C"

run_launcher() {
    HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$TEST_CONFIG" \
        XDG_STATE_HOME="$TEST_STATE" \
        ARIA2C_BIN="$MOCK_ARIA2C" \
        MOCK_CAPTURE="$MOCK_CAPTURE" \
        "$ROOT/bin/aria2-daemon"
}

run_launcher

secret_file="$TEST_CONFIG/aria2/rpc-secret"
runtime_config="$TEST_STATE/aria2/daemon.conf"
session_file="$TEST_STATE/aria2/session"
rpc_secret=$(<"$secret_file")

[[ $rpc_secret =~ ^[[:xdigit:]]{64}$ ]]
[[ $(stat -c '%a' "$secret_file") == 600 ]]
[[ $(stat -c '%a' "$runtime_config") == 600 ]]
[[ $(stat -c '%a' "$session_file") == 600 ]]
[[ -d $TEST_HOME/storage/anime ]]
grep -Fqx -- "--conf-path=$runtime_config" "$MOCK_CAPTURE"
grep -Fqx "dir=$TEST_HOME/storage/anime" "$runtime_config"
grep -Fqx "rpc-secret=$rpc_secret" "$runtime_config"
[[ $(grep -c '^rpc-secret=' "$runtime_config") -eq 1 ]]

run_launcher
[[ $(<"$secret_file") == "$rpc_secret" ]]

if rg -q '^rpc-secret=' "$ROOT/dotfiles/downloads/aria2/daemon.conf"; then
    printf 'The committed aria2 configuration must not contain an RPC secret.\n' >&2
    exit 1
fi

grep -Fqx 'ExecStart=%h/.local/bin/aria2-daemon' \
    "$ROOT/dotfiles/systemd/user/aria2.service"
grep -Fqx 'Restart=on-failure' "$ROOT/dotfiles/systemd/user/aria2.service"
grep -Fqx 'WantedBy=default.target' "$ROOT/dotfiles/systemd/user/aria2.service"
rg -q 'systemctl --user enable --now aria2\.service' "$ROOT/install.sh"

if command -v aria2c >/dev/null 2>&1; then
    aria2c --conf-path="$runtime_config" --enable-rpc=false --dry-run=true \
        >/dev/null
fi

printf 'aria2 daemon tests passed.\n'
