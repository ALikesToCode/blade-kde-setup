#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

DRY_RUN=0
TEMPORARY=
DESIRED_SETTING='enabled-reasoning-efforts = ["low", "medium", "high", "xhigh", "max", "ultra"]'

usage() {
    cat <<'EOF'
Usage: ./scripts/configure-codex-desktop.sh [--dry-run]

Adds Max to the Codex Desktop reasoning-effort picker without replacing other
Codex settings. An existing config is backed up before it is changed.
EOF
}

while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'configure-codex-desktop: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cleanup() {
    [[ -z $TEMPORARY ]] || rm -f -- "$TEMPORARY"
}
trap cleanup EXIT

config_file=${BLADE_CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}
backup_root=${BLADE_BACKUP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/$(date +%Y%m%d-%H%M%S-%N)}

[[ ! -L $config_file ]] || {
    printf 'configure-codex-desktop: refusing symlink target: %s\n' "$config_file" >&2
    exit 1
}
[[ ! -e $config_file || -f $config_file ]] || {
    printf 'configure-codex-desktop: target is not a regular file: %s\n' "$config_file" >&2
    exit 1
}

if [[ -f $config_file ]]; then
    python3 - "$config_file" <<'PY'
import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as stream:
    tomllib.load(stream)
PY
fi

TEMPORARY=$(mktemp)
if [[ -f $config_file ]]; then
    awk -v desired="$DESIRED_SETTING" '
        BEGIN { in_desktop = 0; found_desktop = 0; wrote = 0; skipping = 0 }
        skipping {
            if (index($0, "]") != 0) skipping = 0
            next
        }
        /^[[:space:]]*\[desktop\][[:space:]]*(#.*)?$/ {
            if (!found_desktop) {
                print
                print desired
                found_desktop = 1
                in_desktop = 1
                wrote = 1
                next
            }
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ { in_desktop = 0 }
        in_desktop && /^[[:space:]]*enabled-reasoning-efforts[[:space:]]*=/ {
            if (!wrote) {
                print desired
                wrote = 1
            }
            if (index($0, "]") == 0) skipping = 1
            next
        }
        { print }
        END {
            if (!found_desktop) {
                if (NR != 0) print ""
                print "[desktop]"
                print desired
            }
        }
    ' "$config_file" >"$TEMPORARY"
else
    printf '[desktop]\n%s\n' "$DESIRED_SETTING" >"$TEMPORARY"
fi

python3 - "$TEMPORARY" <<'PY'
import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as stream:
    tomllib.load(stream)
PY

if [[ -f $config_file ]] && cmp -s -- "$TEMPORARY" "$config_file"; then
    printf 'Codex Desktop reasoning efforts are already configured.\n'
    exit 0
fi
if ((DRY_RUN)); then
    printf 'Would merge Codex Desktop Max mode into %s\n' "$config_file"
    exit 0
fi

mode=600
if [[ -f $config_file ]]; then
    mode=$(stat -Lc '%a' -- "$config_file")
    relative=${config_file#/}
    backup_file="$backup_root/$relative"
    [[ ! -e $backup_file && ! -L $backup_file ]] || {
        printf 'configure-codex-desktop: backup already exists: %s\n' "$backup_file" >&2
        exit 1
    }
    install -d -m 700 -- "$(dirname -- "$backup_file")"
    cp -a -- "$config_file" "$backup_file"
fi

config_dir=$(dirname -- "$config_file")
if [[ ! -d $config_dir ]]; then
    [[ ! -e $config_dir && ! -L $config_dir ]] || {
        printf 'configure-codex-desktop: config parent is not a directory: %s\n' \
            "$config_dir" >&2
        exit 1
    }
    install -d -m 700 -- "$config_dir"
fi
install -m "$mode" -- "$TEMPORARY" "$config_file"
printf 'Configured Codex Desktop reasoning efforts in %s\n' "$config_file"
