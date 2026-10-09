#!/usr/bin/env bash
# Give Android Virtual Devices the host GPU and more of the workstation.
# ARTEMIS starts emulators with a bare `emulator -avd NAME`, so each AVD's
# config.ini decides; software rendering and 4 cores made UI tests crawl.

set -Eeuo pipefail

DRY_RUN=0
CORES=8
RAM_MIB=4096
AVD_HOME=${ANDROID_AVD_HOME:-$HOME/.android/avd}
BACKUP_ROOT=${BLADE_BACKUP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/avd-$(date +%Y%m%d-%H%M%S-%N)}

usage() {
    printf 'Usage: %s [--dry-run] [AVD...]\n' "$0"
    printf 'Enable host GPU rendering and raise each AVD to at least %d cores and %d MiB.\n' \
        "$CORES" "$RAM_MIB"
    printf 'Without names, tunes every AVD in %s. Running AVDs are skipped.\n' "$AVD_HOME"
}

names=()
while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) usage >&2; exit 2 ;;
        *) names+=("$1") ;;
    esac
    shift
done
if ((${#names[@]} == 0)); then
    for directory in "$AVD_HOME"/*.avd; do
        [[ -d $directory ]] && names+=("$(basename -- "$directory" .avd)")
    done
fi
((${#names[@]})) || { printf 'No AVDs found in %s.\n' "$AVD_HOME"; exit 0; }

value_of() { sed -n "s/^$2[[:space:]]*=[[:space:]]*//p" "$1" | tail -1; }

ram_mib() {
    case $1 in
        *[Gg]) printf '%d' $((${1%[Gg]} * 1024)) ;;
        *[Mm]) printf '%d' "${1%[Mm]}" ;;
        '') printf '0' ;;
        *) printf '%d' "$1" ;;
    esac
}

for name in "${names[@]}"; do
    config="$AVD_HOME/$name.avd/config.ini"
    [[ -f $config ]] || { printf 'Skipping %s: no %s\n' "$name" "$config" >&2; continue; }
    if pgrep -f -- "qemu-system.*-avd $name( |$)" >/dev/null; then
        printf 'Skipping %s: its emulator is running; rerun after it exits.\n' "$name"
        continue
    fi
    declare -A wanted=([hw.gpu.enabled]=yes [hw.gpu.mode]=host)
    current_cores=$(value_of "$config" 'hw\.cpu\.ncore')
    ((${current_cores:-0} >= CORES)) || wanted[hw.cpu.ncore]=$CORES
    (($(ram_mib "$(value_of "$config" 'hw\.ramSize')") >= RAM_MIB)) || wanted[hw.ramSize]="${RAM_MIB}M"

    rendered=$(mktemp)
    cp -- "$config" "$rendered"
    for key in "${!wanted[@]}"; do
        pattern=${key//./\\.}
        if grep -q "^$pattern[[:space:]]*=" "$rendered"; then
            sed -i "s/^$pattern[[:space:]]*=.*/$key = ${wanted[$key]}/" "$rendered"
        else
            printf '%s = %s\n' "$key" "${wanted[$key]}" >>"$rendered"
        fi
    done
    unset wanted
    if cmp -s -- "$config" "$rendered"; then
        printf '%s is already tuned.\n' "$name"
    elif ((DRY_RUN)); then
        printf 'Would change %s:\n' "$name"
        diff -u "$config" "$rendered" | grep -E '^[-+][^-+]' || true
    else
        mkdir -p -- "$BACKUP_ROOT/$name.avd"
        cp -a -- "$config" "$BACKUP_ROOT/$name.avd/config.ini"
        cp -- "$rendered" "$config"
        printf 'Tuned %s; the previous config is in %s\n' "$name" "$BACKUP_ROOT/$name.avd"
    fi
    rm -f -- "$rendered"
done
