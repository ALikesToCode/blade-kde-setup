#!/usr/bin/env bash
# Point the ~/Windows fstab entry at the Windows partition by UUID. NVMe device
# names change between boots, so the old /dev/nvme…p3 entry stopped matching.
# The entry is noauto: the partition mounts only when opened, and ntfs3 refuses
# to write to it if Windows ever left it hibernated.

set -Eeuo pipefail

SCRIPTS=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
DEVICE=
MOUNT_POINT=$HOME/Windows
FSTAB=${BLADE_FSTAB:-/etc/fstab}

usage() {
    printf 'Usage: %s [--dry-run] [--device /dev/PARTITION]\n' "$0"
    printf 'Without --device, uses the only NTFS partition not mounted at ~/storage.\n'
}

while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        --device) shift; DEVICE=${1:?--device needs a partition} ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

if [[ -z $DEVICE ]]; then
    storage=$(findmnt -no SOURCE --mountpoint "$HOME/storage" 2>/dev/null || true)
    mapfile -t candidates < <(lsblk -rno PATH,FSTYPE | awk -v skip="$storage" '$2 == "ntfs" && $1 != skip {print $1}')
    ((${#candidates[@]} == 1)) || {
        printf 'fix-windows-mount: found %d candidate NTFS partitions; pass --device.\n' \
            "${#candidates[@]}" >&2
        exit 1
    }
    DEVICE=${candidates[0]}
fi
uuid=$(lsblk -no UUID -- "$DEVICE")
[[ -n $uuid && $(lsblk -no FSTYPE -- "$DEVICE") == ntfs ]] || {
    printf 'fix-windows-mount: %s is not an NTFS partition with a UUID.\n' "$DEVICE" >&2
    exit 1
}

options="noauto,nofail,user,uid=$(id -u),gid=$(id -g),umask=022,windows_names"
rendered=$(mktemp)
trap 'rm -f -- "$rendered"' EXIT
python3 "$SCRIPTS/fstab-entry.py" "$FSTAB" "$MOUNT_POINT" "UUID=$uuid" ntfs3 "$options" 0 0 >"$rendered"
if cmp -s -- "$FSTAB" "$rendered"; then
    printf '%s already mounts %s by UUID.\n' "$MOUNT_POINT" "$DEVICE"
    exit 0
fi
diff -u "$FSTAB" "$rendered" || true
findmnt --verify --tab-file "$rendered" >/dev/null || {
    printf 'fix-windows-mount: findmnt rejected the new fstab; nothing changed.\n' >&2
    exit 1
}
if ((DRY_RUN)); then
    printf 'Dry run: %s was not changed.\n' "$FSTAB"
    exit 0
fi
sudo cp -a -- "$FSTAB" "$FSTAB.blade-$(date +%Y%m%d-%H%M%S)"
sudo install -m 644 -- "$rendered" "$FSTAB"
sudo systemctl daemon-reload
mkdir -p -- "$MOUNT_POINT"
printf 'Updated %s. Open the Windows partition with: mount %s\n' "$FSTAB" "$MOUNT_POINT"
