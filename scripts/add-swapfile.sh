#!/usr/bin/env bash
# Add a disk swapfile below zram's priority. zram still takes pages first; the
# disk only receives them once zram is full, instead of the OOM killer firing.

set -Eeuo pipefail

DRY_RUN=0
SIZE=16G
SWAPFILE=/swapfile
PRIORITY=10

usage() {
    printf 'Usage: %s [--dry-run] [--size 16G]\n' "$0"
    printf 'Create, enable, and record %s at swap priority %d.\n' "$SWAPFILE" "$PRIORITY"
}

while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        --size) shift; SIZE=${1-} ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done
[[ $SIZE =~ ^[1-9][0-9]*G$ ]] || { printf 'add-swapfile: --size must look like 16G\n' >&2; exit 2; }

run() {
    if ((DRY_RUN)); then
        printf '  $'; printf ' %q' "$@"; printf '\n'
    else
        sudo "$@"
    fi
}

if swapon --show=NAME --noheadings | grep -Fxq "$SWAPFILE"; then
    printf '%s is already active.\n' "$SWAPFILE"
    exit 0
fi
[[ ! -e $SWAPFILE ]] || {
    printf 'add-swapfile: %s exists but is not active; inspect it before reusing it.\n' "$SWAPFILE" >&2
    exit 1
}
filesystem=$(findmnt -no FSTYPE --target "$(dirname -- "$SWAPFILE")")
[[ $filesystem == ext4 || $filesystem == xfs ]] || {
    printf 'add-swapfile: %s is on %s; only ext4 and xfs are handled here.\n' "$SWAPFILE" "$filesystem" >&2
    exit 1
}

run fallocate -l "$SIZE" "$SWAPFILE"
run chmod 600 "$SWAPFILE"
run mkswap "$SWAPFILE"
run swapon --priority "$PRIORITY" "$SWAPFILE"
entry="$SWAPFILE none swap defaults,pri=$PRIORITY 0 0"
if ! grep -Eq "^[[:space:]]*$SWAPFILE[[:space:]]" /etc/fstab; then
    run cp -a /etc/fstab "/etc/fstab.blade-$(date +%Y%m%d-%H%M%S)"
    if ((DRY_RUN)); then
        printf '  append to /etc/fstab: %s\n' "$entry"
    else
        printf '%s\n' "$entry" | sudo tee -a /etc/fstab >/dev/null
    fi
fi
((DRY_RUN)) || swapon --show
