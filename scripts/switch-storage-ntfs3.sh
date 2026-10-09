#!/usr/bin/env bash
# Mount an NTFS data drive with the in-kernel ntfs3 driver instead of FUSE
# ntfs-3g from the next boot. Never remounts: agents keep working until then.

set -Eeuo pipefail

DRY_RUN=0
MOUNT_POINT=$HOME/storage
FSTAB=${BLADE_FSTAB:-/etc/fstab}

usage() {
    printf 'Usage: %s [--dry-run] [--mount-point DIR]\n' "$0"
    printf 'Switch the ntfs-3g fstab entry for DIR (default ~/storage) to ntfs3.\n'
}

while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        --mount-point) shift; MOUNT_POINT=${1-} ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

grep -qw ntfs3 /proc/filesystems || modinfo ntfs3 >/dev/null 2>&1 || {
    printf 'switch-storage-ntfs3: this kernel has no ntfs3 driver.\n' >&2
    exit 1
}

rendered=$(mktemp)
trap 'rm -f -- "$rendered"' EXIT
awk -v mount="$MOUNT_POINT" '
    !/^[[:space:]]*#/ && $2 == mount && $3 == "ntfs-3g" { $3 = "ntfs3"; changed++ }
    { print }
    END { exit changed == 1 ? 0 : 3 }
' "$FSTAB" >"$rendered" || {
    if awk -v mount="$MOUNT_POINT" '!/^[[:space:]]*#/ && $2 == mount && $3 == "ntfs3" { found = 1 } END { exit !found }' "$FSTAB"; then
        printf '%s already mounts with ntfs3.\n' "$MOUNT_POINT"
        exit 0
    fi
    printf 'switch-storage-ntfs3: no single ntfs-3g entry for %s in %s.\n' "$MOUNT_POINT" "$FSTAB" >&2
    exit 1
}

diff -u "$FSTAB" "$rendered" || true
findmnt --verify --tab-file "$rendered" >/dev/null || {
    printf 'switch-storage-ntfs3: findmnt rejected the new fstab; nothing changed.\n' >&2
    exit 1
}
if ((DRY_RUN)); then
    printf 'Dry run: %s was not changed.\n' "$FSTAB"
    exit 0
fi
backup="$FSTAB.blade-$(date +%Y%m%d-%H%M%S)"
sudo cp -a -- "$FSTAB" "$backup"
sudo install -m 644 -- "$rendered" "$FSTAB"
printf 'Updated %s; the backup is %s.\n' "$FSTAB" "$backup"
printf '%s switches to ntfs3 at the next boot. If it does not mount, restore the backup.\n' "$MOUNT_POINT"
