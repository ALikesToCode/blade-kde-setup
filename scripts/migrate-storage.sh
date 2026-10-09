#!/usr/bin/env bash
# Reformat ~/storage from NTFS to ext4 without losing its contents: copy it to
# a staging directory on another filesystem, verify the copy, reformat the
# partition, copy everything back, and verify again. Every step stops on a
# mismatch, and only the separate `finish` step deletes the staging copy.

set -Eeuo pipefail

SELF=$(readlink -f -- "${BASH_SOURCE[0]}")
ORIGIN=${BLADE_MIGRATE_ORIGIN:-$SELF}
SCRIPTS=$(dirname -- "$SELF")
MOUNT_POINT=${BLADE_STORAGE:-$HOME/storage}
STAGING=/storage-staging
CHECKSUM=0
FSTAB=/etc/fstab
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/blade-storage-migration
# User services that keep files open under ~/storage.
UNITS=(aria2.service aria2-trackers.timer mpd-mpris.service mpd.service mympd.service
    blade-music-sync.timer)

usage() {
    cat <<'EOF'
Usage: migrate-storage.sh [--staging DIR] [--checksum] STEP

Steps, in order (all = copy, format, restore):
  check     Report the partition, free staging space, and anything using it
  copy      Stop the services that use ~/storage, copy it to DIR, and verify
  format    Unmount, reformat the partition as ext4, and mount it by UUID
  restore   Copy everything back, verify, and restart the services
  finish    Delete the staging copy once you have checked your files

Options:
  --staging DIR  Staging directory on another filesystem (default /storage-staging)
  --checksum     Also compare file contents when verifying (slower)
EOF
}

step=
while (($#)); do
    case $1 in
        --staging) shift; STAGING=${1:?--staging needs a directory} ;;
        --checksum) CHECKSUM=1 ;;
        -h|--help) usage; exit 0 ;;
        check|copy|format|restore|finish|all) step=$1 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done
[[ -n $step ]] || { usage >&2; exit 2; }

# This file normally lives inside ~/storage; bash reads scripts as it runs, so
# run from a copy that survives the unmount.
if [[ $SELF == "$MOUNT_POINT"/* ]]; then
    runtime=${XDG_RUNTIME_DIR:-/tmp}/blade-storage-migration
    mkdir -p -m 700 -- "$runtime"
    cp -- "$SELF" "$SCRIPTS/fstab-entry.py" "$runtime/"
    cd -- "$HOME"
    rerun=(--staging "$STAGING")
    ((CHECKSUM)) && rerun+=(--checksum)
    BLADE_MIGRATE_ORIGIN=$SELF exec bash "$runtime/migrate-storage.sh" "${rerun[@]}" "$step"
fi
rsync_check=()
((CHECKSUM)) && rsync_check=(--checksum)
cd -- "$HOME"
mkdir -p -m 700 -- "$STATE"

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'migrate-storage: %s\n' "$*" >&2; exit 1; }
done_step() { [[ -e $STATE/$1 ]]; }
mark() { touch -- "$STATE/$1"; }

device() { findmnt -no SOURCE --mountpoint "$MOUNT_POINT" 2>/dev/null || true; }
fs_type() { findmnt -no FSTYPE --mountpoint "$MOUNT_POINT" 2>/dev/null || true; }

busy() {
    local pids
    pids=$(fuser -m "$MOUNT_POINT" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' || true)
    [[ -n $pids ]] || return 1
    printf 'Still using %s (processes per program):\n' "$MOUNT_POINT"
    # shellcheck disable=SC2086
    ps -o comm= -p $(printf '%s,' $pids | sed 's/,$//') | sort | uniq -c | sort -rn | sed 's/^/  /'
    printf '  Full list: fuser -vm %s\n' "$MOUNT_POINT"
}

stop_units() {
    local unit
    : >"$STATE/units"
    for unit in "${UNITS[@]}"; do
        if systemctl --user is-active --quiet "$unit"; then
            printf '%s\n' "$unit" >>"$STATE/units"
            systemctl --user stop "$unit"
        fi
    done
    command -v balooctl6 >/dev/null && balooctl6 suspend >/dev/null 2>&1 || true
}

start_units() {
    [[ -s $STATE/units ]] && xargs -r systemctl --user start <"$STATE/units"
    command -v balooctl6 >/dev/null && balooctl6 resume >/dev/null 2>&1 || true
}

# Counts entries by type plus total regular-file bytes, then lists any entry
# rsync would still change. Both must be clean.
verify() {
    local source=$1 target=$2 left right differences
    say "Verifying $target against $source"
    left=$(find "$source" -xdev -printf '%y %s\n' | awk '{n[$1]++; if ($1 == "f") b += $2}
        END {for (t in n) printf "%s=%d ", t, n[t]; printf "bytes=%d\n", b}' | tr ' ' '\n' | sort | xargs)
    right=$(find "$target" -xdev -path "$target/lost+found" -prune -o -printf '%y %s\n' \
        | awk '{n[$1]++; if ($1 == "f") b += $2}
        END {for (t in n) printf "%s=%d ", t, n[t]; printf "bytes=%d\n", b}' | tr ' ' '\n' | sort | xargs)
    printf '  source: %s\n  target: %s\n' "$left" "$right"
    differences=$(rsync -aHn --itemize-changes "${rsync_check[@]}" \
        --exclude=/lost+found "$source/" "$target/" | head -20)
    [[ $left == "$right" && -z $differences ]] || {
        printf '%s\n' "$differences"
        die "verification failed; nothing was deleted"
    }
    printf '  identical\n'
}

check() {
    say "Checking $MOUNT_POINT"
    local source type used available
    source=$(device); type=$(fs_type)
    [[ -n $source ]] || die "$MOUNT_POINT is not mounted"
    printf '  partition: %s (%s, label %s, partlabel %s)\n' "$source" "$type" \
        "$(lsblk -no LABEL "$source")" "$(lsblk -no PARTLABEL "$source")"
    if [[ $type == ext4 ]]; then
        printf '  already ext4\n'
        return 0
    fi
    used=$(df -B1 --output=used "$MOUNT_POINT" | tail -1)
    available=$(df -B1 --output=avail "$(dirname -- "$STAGING")" | tail -1)
    printf '  used: %s, free for staging at %s: %s\n' \
        "$(numfmt --to=iec "$used")" "$STAGING" "$(numfmt --to=iec "$available")"
    [[ $(findmnt -no SOURCE --target "$(dirname -- "$STAGING")") != "$source" ]] \
        || die "the staging directory must be on another filesystem"
    ((available > used + used / 20)) || die "not enough free space for the staging copy"
    local unit active=()
    for unit in "${UNITS[@]}"; do
        systemctl --user is-active --quiet "$unit" && active+=("$unit")
    done
    printf '  services that will be stopped and restarted: %s\n' "${active[*]:-none}"
    if busy; then
        printf '  Close these (and cd out of %s in every terminal) before copy.\n' "$MOUNT_POINT"
    else
        printf '  nothing else is using it\n'
    fi
}

copy() {
    [[ $(fs_type) != ext4 ]] || die "$MOUNT_POINT is already ext4"
    check
    say "Stopping services that use $MOUNT_POINT"
    stop_units
    if busy; then
        start_units
        die "close the programs above, then run copy again"
    fi
    say "Copying $MOUNT_POINT to $STAGING"
    if [[ ! -d $STAGING ]]; then
        sudo install -d -o "$(id -u)" -g "$(id -g)" -m 700 -- "$STAGING"
    elif [[ ! -e $STAGING/.blade-storage-migration ]] && [[ -n $(ls -A -- "$STAGING") ]]; then
        die "$STAGING already has other files; choose another --staging"
    fi
    touch -- "$STAGING/.blade-storage-migration"
    rsync -aH --info=progress2 --no-inc-recursive "$MOUNT_POINT/" "$STAGING/data/"
    verify "$MOUNT_POINT" "$STAGING/data"
    printf '%s\n' "$(device)" >"$STATE/device"
    mark copied
}

format() {
    done_step copied || die "run copy first"
    [[ $(fs_type) != ext4 ]] || { printf '%s is already ext4.\n' "$MOUNT_POINT"; return 0; }
    local source uuid rendered answer
    source=$(<"$STATE/device")
    [[ $(device) == "$source" ]] || die "$MOUNT_POINT is no longer $source"
    busy && die "close the programs above, then run format again"
    say "About to erase $source and create an ext4 filesystem"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT "$source"
    printf 'The verified copy is in %s/data.\nType %s to erase it: ' "$STAGING" "$source"
    read -r answer
    [[ $answer == "$source" ]] || die "not confirmed; nothing changed"
    sudo umount -- "$MOUNT_POINT"
    sudo wipefs -a -- "$source"
    sudo mkfs.ext4 -F -L storage -m 0 -- "$source"
    [[ $(sudo blkid -p -o value -s TYPE -- "$source") == ext4 ]] || die "$source did not format as ext4"
    uuid=$(sudo blkid -o value -s UUID -- "$source")
    rendered=$(mktemp)
    python3 "$SCRIPTS/fstab-entry.py" "$FSTAB" "$MOUNT_POINT" "UUID=$uuid" ext4 noatime,nofail 0 2 \
        >"$rendered"
    diff -u "$FSTAB" "$rendered" || true
    findmnt --verify --tab-file "$rendered" >/dev/null || die "findmnt rejected the new fstab"
    sudo cp -a -- "$FSTAB" "$FSTAB.blade-$(date +%Y%m%d-%H%M%S)"
    sudo install -m 644 -- "$rendered" "$FSTAB"
    rm -f -- "$rendered"
    sudo systemctl daemon-reload
    sudo mount -- "$MOUNT_POINT"
    sudo chown "$(id -u):$(id -g)" -- "$MOUNT_POINT"
    sudo chmod 700 -- "$MOUNT_POINT"
    [[ $(fs_type) == ext4 ]] || die "$MOUNT_POINT did not mount as ext4"
    mark formatted
}

restore() {
    done_step formatted || die "run format first"
    [[ $(fs_type) == ext4 ]] || die "$MOUNT_POINT is not the new ext4 filesystem"
    say "Copying $STAGING/data back to $MOUNT_POINT"
    rsync -aH --info=progress2 --no-inc-recursive "$STAGING/data/" "$MOUNT_POINT/"
    verify "$STAGING/data" "$MOUNT_POINT"
    mark restored
    say "Restarting services"
    start_units
    printf '\n%s is ext4 with all files restored. Check them, then run:\n  %s finish\n' \
        "$MOUNT_POINT" "$ORIGIN"
}

finish() {
    done_step restored || die "run restore first"
    local answer
    printf 'Delete the staging copy %s (%s)? Type delete: ' "$STAGING" \
        "$(du -sh -- "$STAGING" 2>/dev/null | cut -f1)"
    read -r answer
    [[ $answer == delete ]] || die "not confirmed; kept $STAGING"
    sudo rm -rf --one-file-system -- "$STAGING"
    rm -rf -- "$STATE"
    printf 'Removed %s.\n' "$STAGING"
}

case $step in
    check) check ;;
    copy) copy ;;
    format) format ;;
    restore) restore ;;
    finish) finish ;;
    all) sudo -v; copy; format; restore ;;
esac
