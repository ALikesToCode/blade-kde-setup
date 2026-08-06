#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
trap 'printf "aria2 tracker test failed at line %s\n" "$LINENO" >&2' ERR

TEST_HOME="$TEST_ROOT/home"
TEST_CONFIG="$TEST_HOME/.config"
TEST_STATE="$TEST_HOME/.local/state"
SOURCE_ONE="$TEST_ROOT/source-one.txt"
SOURCE_TWO="$TEST_ROOT/source-two.txt"
SOURCE_BAD="$TEST_ROOT/source-bad.txt"
MOCK_CURL="$TEST_ROOT/curl"
RPC_PAYLOAD="$TEST_ROOT/rpc-payload.json"

mkdir -p -- "$TEST_CONFIG/aria2" "$TEST_STATE/aria2"
printf '%064d\n' 0 > "$TEST_CONFIG/aria2/rpc-secret"
cat > "$TEST_STATE/aria2/daemon.conf" <<'EOF'
enable-rpc=true
rpc-listen-port=14141
EOF
cat > "$SOURCE_ONE" <<'EOF'
udp://93.158.213.92:6969/announce

http://34.66.57.33:80/announce
wss://tracker.example/announce
EOF
cat > "$SOURCE_TWO" <<'EOF'
http://34.66.57.33:80/announce
https://tracker.example/announce
http://127.0.0.1:8080/announce
udp://185.121.168.96:1337/announce
udp://95.217.80.20:6969/announce
EOF
printf 'javascript:alert(1)\n' > "$SOURCE_BAD"

cat > "$MOCK_CURL" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
output=
payload=
url=
while (($#)); do
    case $1 in
        --output) output=$2; shift 2 ;;
        --data-binary) payload=$2; shift 2 ;;
        --connect-timeout|--max-time|--max-filesize|--proto|--retry|--header)
            shift 2
            ;;
        --fail|--location|--silent|--show-error|--tlsv1.2) shift ;;
        *) url=$1; shift ;;
    esac
done
case $url in
    https://source-one) cp -- "$MOCK_SOURCE_ONE" "$output" ;;
    https://source-two) cp -- "$MOCK_SOURCE_TWO" "$output" ;;
    https://source-bad) cp -- "$MOCK_SOURCE_BAD" "$output" ;;
    http://127.0.0.1:14141/jsonrpc)
        printf '%s\n' "$payload" > "$MOCK_RPC_PAYLOAD"
        printf '{"jsonrpc":"2.0","id":"trackers","result":"OK"}\n' > "$output"
        ;;
    *) printf 'unexpected URL: %s\n' "$url" >&2; exit 1 ;;
esac
EOF
chmod 0755 -- "$MOCK_CURL"

run_updater() {
    HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$TEST_CONFIG" \
        XDG_STATE_HOME="$TEST_STATE" \
        CURL_BIN="$MOCK_CURL" \
        JQ_BIN="$(command -v jq)" \
        MOCK_SOURCE_ONE="$SOURCE_ONE" \
        MOCK_SOURCE_TWO="$SOURCE_TWO" \
        MOCK_SOURCE_BAD="$SOURCE_BAD" \
        MOCK_RPC_PAYLOAD="$RPC_PAYLOAD" \
        ARIA2_TRACKER_SOURCES="$1" \
        ARIA2_TRACKER_LIMIT=4 \
        ARIA2_TRACKER_MINIMUM=3 \
        "$ROOT/bin/aria2-update-trackers"
}

run_updater $'https://source-one\nhttps://source-two'

tracker_config="$TEST_STATE/aria2/trackers.conf"
expected='udp://93.158.213.92:6969/announce,http://34.66.57.33:80/announce,https://tracker.example/announce,udp://185.121.168.96:1337/announce'
[[ $(stat -c '%a' "$tracker_config") == 600 ]]
grep -Fqx "bt-tracker=$expected" "$tracker_config"
jq -e --arg expected "$expected" '
    .method == "aria2.changeGlobalOption"
    and .params[0] == ("token:" + ("0" * 64))
    and .params[1]["bt-tracker"] == $expected
' "$RPC_PAYLOAD" >/dev/null

inode_before=$(stat -c '%i' "$tracker_config")
run_updater $'https://source-one\nhttps://source-two' >/dev/null
[[ $(stat -c '%i' "$tracker_config") == "$inode_before" ]]

checksum_before=$(sha256sum "$tracker_config")
if run_updater 'https://source-bad' >/dev/null 2>&1; then
    printf 'invalid tracker data unexpectedly succeeded\n' >&2
    exit 1
fi
[[ $(sha256sum "$tracker_config") == "$checksum_before" ]]

grep -Fqx 'OnCalendar=daily' \
    "$ROOT/dotfiles/systemd/user/aria2-trackers.timer"
grep -Fqx 'ExecStart=%h/.local/bin/aria2-update-trackers' \
    "$ROOT/dotfiles/systemd/user/aria2-trackers.service"

printf 'aria2 tracker tests passed.\n'
