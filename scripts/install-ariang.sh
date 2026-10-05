#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LOCK_FILE="$ROOT/packages/ariang.lock"
DRY_RUN=0
DOWNLOAD_ROOT=
STAGING_ROOT=

usage() {
    cat <<'EOF'
Usage: ./scripts/install-ariang.sh [--dry-run]

Installs the checksum-pinned AriaNg AllInOne release below
~/.local/share/ariang/releases without replacing older releases.

Environment:
  ARIANG_ARCHIVE  Use an already-downloaded release archive.
EOF
}

while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'install-ariang: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cleanup() {
    [[ -z $STAGING_ROOT ]] || rm -rf -- "$STAGING_ROOT"
    [[ -z $DOWNLOAD_ROOT ]] || rm -rf -- "$DOWNLOAD_ROOT"
}
trap cleanup EXIT

[[ -r $LOCK_FILE ]] || {
    printf 'install-ariang: missing lock file: %s\n' "$LOCK_FILE" >&2
    exit 1
}
mapfile -t lock_records < <(
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$LOCK_FILE"
)
((${#lock_records[@]} == 1)) || {
    printf 'install-ariang: lock file must contain exactly one release\n' >&2
    exit 1
}
IFS='|' read -r version archive_name expected_sha256 url extra \
    <<<"${lock_records[0]}"
[[ -z $extra && $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'install-ariang: invalid release record\n' >&2
    exit 1
}
[[ $archive_name == "AriaNg-$version-AllInOne.zip" ]] || {
    printf 'install-ariang: unexpected archive name\n' >&2
    exit 1
}
[[ $expected_sha256 =~ ^[0-9a-f]{64}$ ]] || {
    printf 'install-ariang: invalid SHA-256 digest\n' >&2
    exit 1
}
[[ $url == "https://github.com/mayswind/AriaNg/releases/download/$version/$archive_name" ]] || {
    printf 'install-ariang: release URL is outside the pinned GitHub location\n' >&2
    exit 1
}

release_parent="${XDG_DATA_HOME:-$HOME/.local/share}/ariang/releases"
target="$release_parent/$version"
printf 'AriaNg plan:\n'
printf '  version: %s\n' "$version"
printf '  source: %s\n' "$url"
printf '  target: %s\n' "$target"
if ((DRY_RUN)); then
    printf '  action: verify the archive and add the versioned release\n'
    exit 0
fi

for command_name in curl sha256sum unzip; do
    command -v "$command_name" >/dev/null 2>&1 || {
        printf 'install-ariang: missing command: %s\n' "$command_name" >&2
        exit 1
    }
done

archive_path=${ARIANG_ARCHIVE-}
if [[ -n $archive_path ]]; then
    archive_path=$(realpath -e -- "$archive_path") || {
        printf 'install-ariang: cannot resolve ARIANG_ARCHIVE\n' >&2
        exit 1
    }
    [[ -f $archive_path && ! -L $archive_path ]] || {
        printf 'install-ariang: ARIANG_ARCHIVE is not a regular file\n' >&2
        exit 1
    }
else
    DOWNLOAD_ROOT=$(mktemp -d)
    archive_path="$DOWNLOAD_ROOT/$archive_name"
    curl --fail --location --proto '=https' --tlsv1.2 \
        --retry 3 --connect-timeout 10 \
        --output "$archive_path" "$url"
fi

actual_sha256=$(sha256sum "$archive_path" | awk '{print $1}')
[[ $actual_sha256 == "$expected_sha256" ]] || {
    printf 'install-ariang: archive checksum mismatch\n' >&2
    exit 1
}

mapfile -t archive_entries < <(unzip -Z1 "$archive_path")
if ((${#archive_entries[@]} != 2)) || \
   [[ ${archive_entries[0]} != index.html || ${archive_entries[1]} != LICENSE ]]; then
    printf 'install-ariang: archive layout is not the reviewed AllInOne layout\n' >&2
    exit 1
fi

install -d -m 0755 "$release_parent"
STAGING_ROOT=$(mktemp -d "$release_parent/.ariang-$version.XXXXXXXX")
unzip -q "$archive_path" -d "$STAGING_ROOT"
[[ -f $STAGING_ROOT/index.html && ! -L $STAGING_ROOT/index.html && \
   -f $STAGING_ROOT/LICENSE && ! -L $STAGING_ROOT/LICENSE ]] || {
    printf 'install-ariang: extracted release contains unsafe files\n' >&2
    exit 1
}
printf '%s\n' "$version" >"$STAGING_ROOT/VERSION"
chmod 0644 "$STAGING_ROOT/index.html" "$STAGING_ROOT/LICENSE" \
    "$STAGING_ROOT/VERSION"

if [[ -d $target && ! -L $target ]]; then
    if diff -qr --no-dereference "$STAGING_ROOT" "$target" >/dev/null 2>&1; then
        printf 'AriaNg %s is already installed.\n' "$version"
        exit 0
    fi
    printf 'install-ariang: preserved unexpected existing release at %s\n' \
        "$target" >&2
    exit 1
fi
[[ ! -e $target && ! -L $target ]] || {
    printf 'install-ariang: unsafe target already exists: %s\n' "$target" >&2
    exit 1
}
mv -- "$STAGING_ROOT" "$target"
STAGING_ROOT=
printf 'AriaNg %s installed at %s\n' "$version" "$target"
