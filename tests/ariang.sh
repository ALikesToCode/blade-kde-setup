#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

lock_file="$ROOT/packages/ariang.lock"
installer="$ROOT/scripts/install-ariang.sh"
server="$ROOT/bin/ariang-server"
launcher="$ROOT/bin/ariang"
service="$ROOT/dotfiles/systemd/user/ariang.service"
desktop="$ROOT/dotfiles/apps/ariang/ariang.desktop"

IFS='|' read -r version archive sha256 url <"$lock_file"
[[ "$version" == 1.3.14 ]]
[[ "$archive" == AriaNg-1.3.14-AllInOne.zip ]]
[[ "$sha256" == 65bc5ed3573ef05313ea953a5c5363c8b33a4996849b2986c78660eab1a9edb2 ]]
[[ "$url" == "https://github.com/mayswind/AriaNg/releases/download/$version/$archive" ]]

TEST_HOME="$TEST_ROOT/home"
release_root="$TEST_HOME/.local/share/ariang/releases/$version"
install -d -m 700 "$TEST_HOME/.config/aria2"
install -d -m 755 "$release_root"
printf '<!doctype html><title>AriaNg</title>\n' >"$release_root/index.html"
printf 'MIT\n' >"$release_root/LICENSE"
printf '%s\n' "$version" >"$release_root/VERSION"
printf '%064d\n' 0 >"$TEST_HOME/.config/aria2/rpc-secret"
chmod 600 "$TEST_HOME/.config/aria2/rpc-secret"

HOME="$TEST_HOME" python "$server" --check >/dev/null

python - "$server" "$release_root" "$TEST_HOME/.config/aria2/rpc-secret" <<'PY'
import functools
import http.client
import importlib.machinery
import importlib.util
import os
import pathlib
import sys
import threading

path = pathlib.Path(sys.argv[1])
ui_root = pathlib.Path(sys.argv[2])
secret_file = pathlib.Path(sys.argv[3])
loader = importlib.machinery.SourceFileLoader("ariang_server", str(path))
spec = importlib.util.spec_from_loader("ariang_server", loader)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
target = module.configuration_target("0" * 64)
assert target.startswith(
    "/?aria2=local#!/settings/rpc/set?protocol=http&host=127.0.0.1"
)
assert "&port=14141&interface=jsonrpc&secret=" in target
assert not target.endswith("0" * 64)

if os.environ.get("ARIANG_TEST_NETWORK") == "1":
    handler = functools.partial(
        module.AriaNgRequestHandler,
        directory=str(ui_root),
        secret_file=secret_file,
    )
    server = module.LocalThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        connection = http.client.HTTPConnection(*server.server_address, timeout=2)
        connection.request("GET", "/healthz")
        response = connection.getresponse()
        assert response.status == 200
        assert response.read() == b"AriaNg 1.3.14\n"
        connection.request("GET", "/")
        response = connection.getresponse()
        assert response.status == 302
        assert response.getheader("Location") == target
        assert response.getheader("Cache-Control") == "no-store"
        response.read()
        connection.request("GET", "/index.html")
        response = connection.getresponse()
        assert response.status == 302
        assert response.getheader("Location") == target
        response.read()
        connection.request("GET", "/?aria2=local")
        response = connection.getresponse()
        assert response.status == 200
        assert response.read() == b"<!doctype html><title>AriaNg</title>\n"
        connection.request("GET", "/configure")
        response = connection.getresponse()
        assert response.status == 302
        assert response.getheader("Location") == target
        assert response.getheader("Cache-Control") == "no-store"
        response.read()
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
PY

grep -Fqx 'ExecStart=%h/.local/bin/ariang-server' "$service"
grep -Fqx 'After=aria2.service' "$service"
grep -Fqx 'Restart=always' "$service"
grep -Fq 'endpoint=http://127.0.0.1:14142' "$launcher"
grep -Fq "\$endpoint/configure" "$launcher"
grep -Fq 'Exec=__HOME__/.local/bin/ariang' "$desktop"
grep -Fq '127.0.0.1' "$server"
grep -Fq 'UI_PORT = 14142' "$server"
grep -Fq 'RPC_PORT = 14141' "$server"
grep -Fq 'aria2 RPC secret' "$server"
grep -Fq 'sha256sum' "$installer"
grep -Fq 'unzip' "$installer"

printf 'AriaNg tests passed.\n'
