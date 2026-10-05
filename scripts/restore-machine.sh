#!/usr/bin/env bash
# Reproduce the machine snapshot recorded by scripts/capture-machine.sh:
# packages, user tools, system tuning, services, groups, and KDE settings.
# Hardware-specific entries follow machine/hardware-rules.tsv, and boot files
# under machine/etc-reference/ are only compared, never installed.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MACHINE=${BLADE_MACHINE_DIR:-$ROOT/machine}
RULES="$MACHINE/hardware-rules.tsv"
BACKUP_ROOT=${BLADE_BACKUP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/machine-$(date +%Y%m%d-%H%M%S)}
DRY_RUN=0
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage: ./scripts/restore-machine.sh [--dry-run] [-y]

Install the recorded packages, user tools, system tuning, services, groups,
and KDE settings from machine/. Existing files are backed up first.

  -n, --dry-run  Print every action without changing the system
  -y, --yes      Use non-interactive package-manager confirmation
EOF
}

while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

section() { printf '\n==> %s\n' "$*"; }
info() { printf '  • %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die() { printf 'restore-machine: %s\n' "$*" >&2; exit 1; }

run() {
    if ((DRY_RUN)); then
        printf '  $'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

[[ -d $MACHINE/packages ]] || die "no snapshot in $MACHINE; run scripts/capture-machine.sh first"

# Hardware gates come from sysfs so detection needs no extra packages.
detect_gates() {
    local device class vendor gates=()
    for device in /sys/bus/pci/devices/*; do
        [[ -r $device/class && -r $device/vendor ]] || continue
        class=$(<"$device/class")
        vendor=$(<"$device/vendor")
        [[ $class == 0x03* ]] || continue
        case $vendor in
            0x10de) gates+=(nvidia) ;;
            0x8086) gates+=(intel-gpu) ;;
            0x1002) gates+=(amd-gpu) ;;
        esac
    done
    grep -q GenuineIntel /proc/cpuinfo 2>/dev/null && gates+=(intel-cpu)
    grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null && gates+=(amd-cpu)
    compgen -G '/sys/class/power_supply/BAT*' >/dev/null && gates+=(laptop)
    grep -qi 'micro-star' /sys/class/dmi/id/sys_vendor 2>/dev/null && gates+=(msi)
    local IFS=,
    printf '%s' "${gates[*]}"
}

GATES=${BLADE_MACHINE_GATES-$(detect_gates)}

entries() {
    grep -v '^[[:space:]]*$' "$1" | python3 "$ROOT/scripts/machine-filter.py" "$RULES" "$GATES"
}

report_skipped() {
    local skipped
    skipped=$(grep -v '^[[:space:]]*$' "$1" \
        | python3 "$ROOT/scripts/machine-filter.py" "$RULES" "$GATES" --skipped)
    [[ -n $skipped ]] || return 0
    info "Held back for absent hardware: $(cut -f1 <<<"$skipped" | tr '\n' ' ')"
}

backup_target() {
    local target=$1
    [[ -e $target ]] || return 0
    if ((DRY_RUN)); then
        printf '  backup %q -> %q\n' "$target" "$BACKUP_ROOT${target}"
        return 0
    fi
    if [[ -w $(dirname -- "$target") ]]; then
        mkdir -p -- "$BACKUP_ROOT$(dirname -- "$target")"
        cp -a -- "$target" "$BACKUP_ROOT$target"
    else
        sudo mkdir -p -- "$BACKUP_ROOT$(dirname -- "$target")"
        sudo cp -a -- "$target" "$BACKUP_ROOT$target"
    fi
}

render() {
    sed -e "s|__HOME__|${HOME//&/\\&}|g" -e "s|^__USER__\$|$(id -un)|" "$1"
}

restore_packages() {
    section 'Packages'
    local -a pacman_args=(--needed) yay_args=(--needed) available=() missing=() aur=()
    ((ASSUME_YES)) && pacman_args+=(--noconfirm) && yay_args+=(--noconfirm)

    if grep -q '^lib32-' "$MACHINE/packages/pacman.txt" && ! pacman-conf --repo-list | grep -qx multilib; then
        info 'Enabling the multilib repository required by the lib32 packages'
        backup_target /etc/pacman.conf
        run sudo sed -i '/^#\[multilib\]$/,/^#Include/ s/^#//' /etc/pacman.conf
    fi
    run sudo pacman -Sy

    local sync_list
    sync_list=$(mktemp)
    pacman -Slq | LC_ALL=C sort -u >"$sync_list"
    mapfile -t available < <(entries "$MACHINE/packages/pacman.txt" | LC_ALL=C comm -12 - "$sync_list")
    mapfile -t missing < <(entries "$MACHINE/packages/pacman.txt" | LC_ALL=C comm -23 - "$sync_list")
    mapfile -t aur < <(entries "$MACHINE/packages/aur.txt"; printf '%s\n' "${missing[@]}")
    rm -f -- "$sync_list"
    report_skipped "$MACHINE/packages/pacman.txt"
    report_skipped "$MACHINE/packages/aur.txt"

    # Upgrade in the same transaction; installing after a bare -Sy would be a
    # partial upgrade.
    ((${#available[@]} == 0)) || run sudo pacman -Syu "${pacman_args[@]}" "${available[@]}"
    mapfile -t aur < <(printf '%s\n' "${aur[@]}" | grep -v '^$' | grep -vx yay || true)
    ((${#aur[@]})) || return 0
    if ! command -v yay >/dev/null 2>&1; then
        warn "Yay is missing; install it, then re-run. Pending: ${aur[*]}"
        return 0
    fi
    # One package per transaction, so a package that left the AUR or needs a
    # third-party repository does not block the rest.
    local package
    for package in "${aur[@]}"; do
        run yay -S "${yay_args[@]}" "$package" || warn "Not installed: $package"
    done
}

restore_user_tools() {
    section 'User command-line tools'
    local package
    if command -v pnpm >/dev/null 2>&1; then
        while IFS= read -r package; do
            [[ $package == pnpm@* ]] && continue
            run pnpm add --global "$package"
        done < <(grep -v '^$' "$MACHINE/packages/pnpm-global.txt")
    fi
    if command -v npm >/dev/null 2>&1; then
        while IFS= read -r package; do
            run npm install --global --prefix "$HOME/.local" --no-audit --no-fund "$package"
        done < <(grep -v '^$' "$MACHINE/packages/npm-global.txt")
    fi
    if command -v uv >/dev/null 2>&1; then
        while IFS= read -r package; do
            run uv tool install "$package"
        done < <(grep -v '^$' "$MACHINE/packages/uv-tools.txt")
    fi
    if command -v pipx >/dev/null 2>&1; then
        while IFS= read -r package; do
            run pipx install "$package"
        done < <(grep -v '^$' "$MACHINE/packages/pipx.txt")
    fi
    if [[ -s $MACHINE/packages/flatpak.txt ]] && command -v flatpak >/dev/null 2>&1; then
        while IFS= read -r package; do
            run flatpak install --user -y flathub "$package"
        done < <(grep -v '^$' "$MACHINE/packages/flatpak.txt")
    fi
}

restore_system_files() {
    section 'System tuning'
    local source target mode rendered changed=()
    while IFS= read -r target; do
        source="$MACHINE/etc$target"
        mode=$(stat -c '%a' -- "$source")
        rendered=$(mktemp)
        render "$source" >"$rendered"
        if [[ -r $target ]] && cmp -s "$rendered" "$target"; then
            rm -f -- "$rendered"
            continue
        fi
        backup_target "$target"
        run sudo install -D -m "$mode" -o root -g root "$rendered" "$target"
        rm -f -- "$rendered"
        changed+=("$target")
    done < <(cd "$MACHINE/etc" && find . -type f | sed 's|^\.||' | LC_ALL=C sort | entries /dev/stdin)
    report_skipped <(cd "$MACHINE/etc" && find . -type f | sed 's|^\.||')

    ((${#changed[@]})) || { info 'System files already match the snapshot'; return 0; }
    printf '%s\n' "${changed[@]}" | grep -q '^/etc/locale.gen$' && run sudo locale-gen
    printf '%s\n' "${changed[@]}" | grep -q '^/etc/sysctl.d/' && run sudo sysctl --system
    printf '%s\n' "${changed[@]}" | grep -q '^/etc/udev/' && run sudo udevadm control --reload
    run sudo systemctl daemon-reload
}

restore_services() {
    section 'Services and groups'
    local unit group
    while IFS= read -r unit; do
        systemctl is-enabled --quiet "$unit" 2>/dev/null && continue
        if systemctl list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
            run sudo systemctl enable "$unit"
        else
            warn "System unit not installed: $unit"
        fi
    done < <(entries "$MACHINE/units/system-enabled.txt")
    report_skipped "$MACHINE/units/system-enabled.txt"
    while IFS= read -r unit; do
        [[ $(systemctl is-enabled "$unit" 2>/dev/null) == masked ]] && continue
        run sudo systemctl mask "$unit"
    done < <(entries "$MACHINE/units/system-masked.txt")
    while IFS= read -r unit; do
        systemctl --user is-enabled --quiet "$unit" 2>/dev/null && continue
        if systemctl --user list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
            run systemctl --user enable "$unit"
        else
            warn "User unit not installed: $unit"
        fi
    done < <(entries "$MACHINE/units/user-enabled.txt")
    while IFS= read -r unit; do
        [[ $(systemctl --user is-enabled "$unit" 2>/dev/null) == masked ]] && continue
        run systemctl --user mask "$unit"
    done < <(entries "$MACHINE/units/user-masked.txt")

    while IFS= read -r group; do
        id -nG | tr ' ' '\n' | grep -qx "$group" && continue
        if getent group "$group" >/dev/null; then
            run sudo usermod -aG "$group" "$(id -un)"
        else
            warn "Group does not exist yet: $group"
        fi
    done < <(grep -v '^$' "$MACHINE/units/groups.txt")
}

restore_kde_settings() {
    section 'KDE and desktop settings'
    local source relative result
    while IFS= read -r relative; do
        source="$MACHINE/home/$relative"
        if ((DRY_RUN)); then
            printf '  merge %q -> %q\n' "$source" "$HOME/$relative"
            continue
        fi
        backup_target "$HOME/$relative"
        result=$(python3 "$ROOT/scripts/merge-kde-config.py" <(render "$source") "$HOME/$relative")
        info "$result: ~/$relative"
    done < <(cd "$MACHINE/home" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}

compare_reference_files() {
    section 'Boot and repository files (review only)'
    local reference target
    while IFS= read -r target; do
        reference="$MACHINE/etc-reference$target"
        if [[ -r $target ]] && cmp -s <(render "$reference") "$target"; then
            continue
        fi
        info "Differs from the recorded machine, not changed: $target"
    done < <(cd "$MACHINE/etc-reference" && find . -type f | sed 's|^\.||' | LC_ALL=C sort)
    info "Compare with machine/etc-reference/ and adapt by hand; see docs/MACHINE-SNAPSHOT.md"
}

info "Hardware gates: ${GATES:-none}"
if ((!DRY_RUN)); then
    sudo -v || die 'sudo authentication failed'
fi
restore_packages
restore_user_tools
restore_system_files
restore_services
restore_kde_settings
compare_reference_files
section 'Done'
info 'Log out and back in (or reboot) so services, groups, and KDE settings take effect.'
((DRY_RUN)) || info "Backups: $BACKUP_ROOT"
