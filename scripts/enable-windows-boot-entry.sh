#!/usr/bin/env bash
# Add Windows to the GRUB menu through os-prober, so it boots from GRUB instead
# of only from the firmware boot menu.

set -Eeuo pipefail

DRY_RUN=0
GRUB_DEFAULTS=/etc/default/grub
GRUB_CONFIG=/boot/grub/grub.cfg

case ${1-} in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help) printf 'Usage: %s [--dry-run]\n' "$0"; exit 0 ;;
    '') ;;
    *) printf 'Usage: %s [--dry-run]\n' "$0" >&2; exit 2 ;;
esac
command -v os-prober >/dev/null || {
    printf 'Install os-prober first: sudo pacman -S --needed os-prober\n' >&2
    exit 1
}

rendered=$(mktemp)
trap 'rm -f -- "$rendered"' EXIT
if grep -Eq '^[#[:space:]]*GRUB_DISABLE_OS_PROBER=' "$GRUB_DEFAULTS"; then
    sed -E 's/^[#[:space:]]*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' \
        "$GRUB_DEFAULTS" >"$rendered"
else
    { cat -- "$GRUB_DEFAULTS"; printf 'GRUB_DISABLE_OS_PROBER=false\n'; } >"$rendered"
fi
diff -u "$GRUB_DEFAULTS" "$rendered" || true
if ((DRY_RUN)); then
    printf 'Dry run: would update %s and regenerate %s.\n' "$GRUB_DEFAULTS" "$GRUB_CONFIG"
    exit 0
fi
if ! cmp -s -- "$GRUB_DEFAULTS" "$rendered"; then
    sudo cp -a -- "$GRUB_DEFAULTS" "$GRUB_DEFAULTS.blade-$(date +%Y%m%d-%H%M%S)"
    sudo install -m 644 -- "$rendered" "$GRUB_DEFAULTS"
fi
sudo grub-mkconfig -o "$GRUB_CONFIG"
if sudo grep -q "menuentry '.*Windows" "$GRUB_CONFIG"; then
    printf 'Windows is in the GRUB menu.\n'
else
    printf 'os-prober found no Windows install; the GRUB menu is unchanged.\n' >&2
    exit 1
fi
