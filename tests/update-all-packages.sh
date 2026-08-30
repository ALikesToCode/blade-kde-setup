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
    'install --help')
        if [[ ${MOCK_NPM_SUPPORTS_ALLOW_SCRIPTS:-0} == 1 ]]; then
            printf '%s\n' '  --allow-scripts <package-list>' '--strict-allow-scripts'
        fi
        ;;
    *) exit 99 ;;
esac
EOF

cat > "$MOCK_BIN/node" <<'EOF'
#!/usr/bin/bash
printf 'openwiki'
EOF

cat > "$MOCK_BIN/pnpm" <<'EOF'
#!/usr/bin/bash
case "$*" in
    'help update')
        if [[ ${MOCK_PNPM_SUPPORTS_YES:-0} == 1 ]]; then
            printf '%s\n' '  -y, --yes  Automatically answer yes to prompts'
        fi
        ;;
    *) exit 99 ;;
esac
EOF

chmod 0755 "$MOCK_BIN/npm" "$MOCK_BIN/node" "$MOCK_BIN/pnpm"

run_dry_run() {
    PATH="$MOCK_BIN" \
        HOME="$TEMP_ROOT/home" \
        MOCK_GLOBAL_ROOT="$GLOBAL_ROOT" \
        MOCK_NPM_PREFIX="$NPM_PREFIX" \
        MOCK_PNPM_SUPPORTS_YES="$1" \
        MOCK_NPM_SUPPORTS_ALLOW_SCRIPTS="$2" \
        /usr/bin/bash "$ROOT/bin/update-all-packages" --yes --dry-run
}

output_with_modern_options=$(run_dry_run 1 1)
grep -Fq \
    '$ npm install --global --no-fund --no-audit --allow-scripts=openwiki --strict-allow-scripts openwiki@latest' \
    <<<"$output_with_modern_options"
grep -Fq '$ pnpm update --global --latest --yes' <<<"$output_with_modern_options"

output_without_modern_options=$(run_dry_run 0 0)
grep -Fq '$ npm install --global --no-fund --no-audit openwiki@latest' \
    <<<"$output_without_modern_options"
if grep -Fq -- '--allow-scripts' <<<"$output_without_modern_options"; then
    printf 'npm dry-run used allow-scripts although the installed npm does not support it.\n' >&2
    exit 1
fi
grep -Fq '$ pnpm update --global --latest' <<<"$output_without_modern_options"
if grep -Fq '$ pnpm update --global --latest --yes' <<<"$output_without_modern_options"; then
    printf 'pnpm dry-run used --yes although the installed pnpm does not support it.\n' >&2
    exit 1
fi

if grep -Fq -- '--no-confirm' \
    <<<"$output_with_modern_options$output_without_modern_options"; then
    printf 'pnpm dry-run output still contains unsupported --no-confirm.\n' >&2
    exit 1
fi

printf 'Update-all package-manager tests passed.\n'
