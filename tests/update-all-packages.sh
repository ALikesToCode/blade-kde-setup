#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

MOCK_BIN="$TEMP_ROOT/bin"
GLOBAL_ROOT="$TEMP_ROOT/npm-global"
NPM_PREFIX="$TEMP_ROOT/npm-prefix"
mkdir -p -- "$MOCK_BIN" "$GLOBAL_ROOT/openwiki" "$NPM_PREFIX"
printf '{"name":"openwiki","version":"0.2.0"}\n' \
    > "$GLOBAL_ROOT/openwiki/package.json"

ln -s /usr/bin/find "$MOCK_BIN/find"
ln -s /usr/bin/sort "$MOCK_BIN/sort"

cat > "$MOCK_BIN/npm" <<'EOF'
#!/usr/bin/bash
case "$*" in
    'root -g') printf '%s\n' "$MOCK_GLOBAL_ROOT" ;;
    'config get prefix') printf '%s\n' "$MOCK_NPM_PREFIX" ;;
    *) exit 99 ;;
esac
EOF

cat > "$MOCK_BIN/node" <<'EOF'
#!/usr/bin/bash
printf 'openwiki'
EOF

cat > "$MOCK_BIN/pnpm" <<'EOF'
#!/usr/bin/bash
exit 99
EOF

chmod 0755 "$MOCK_BIN/npm" "$MOCK_BIN/node" "$MOCK_BIN/pnpm"

output=$(
    PATH="$MOCK_BIN" \
        HOME="$TEMP_ROOT/home" \
        MOCK_GLOBAL_ROOT="$GLOBAL_ROOT" \
        MOCK_NPM_PREFIX="$NPM_PREFIX" \
        /usr/bin/bash "$ROOT/bin/update-all-packages" --yes --dry-run
)

grep -Fq '$ npm install --global --no-fund --no-audit openwiki@latest' <<<"$output"
grep -Fq '$ pnpm update --global --latest --yes' <<<"$output"
if grep -Fq -- '--no-confirm' <<<"$output"; then
    printf 'pnpm dry-run output still contains unsupported --no-confirm.\n' >&2
    exit 1
fi

printf 'Update-all package-manager tests passed.\n'
