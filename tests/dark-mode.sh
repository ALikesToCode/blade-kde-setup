#!/usr/bin/env bash

set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Dry-runs must select the custom dark theme without applying any appearance changes.
theme_output=$(bash "$ROOT/scripts/apply-kde.sh" --dry-run)
grep -Fq -- '--key DefaultDarkLookAndFeel --notify org.mysterious.artixdarkrounded.desktop' <<<"$theme_output"

mkdir -p -- "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/kreadconfig6" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$TEST_ACTIVE_THEME"
STUB
chmod +x "$TEST_ROOT/bin/kreadconfig6"

for theme in org.mysterious.artixdarkrounded.desktop org.kde.breeze.desktop; do
    output=$(PATH="$TEST_ROOT/bin:$PATH" TEST_ACTIVE_THEME="$theme" \
        bash "$ROOT/scripts/install-power-control.sh" --dry-run --activate)
    if [[ $theme == org.mysterious.artixdarkrounded.desktop ]]; then
        grep -Fq 'Would set the Dark Mode target to Artix Dark Rounded.' <<<"$output"
    elif grep -Fq 'Would set the Dark Mode target' <<<"$output"; then
        printf 'Power setup must preserve another active theme.\n' >&2
        exit 1
    fi
done
printf 'Dark-mode target dry-run checks passed.\n'
