#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

bash -n "$ROOT/scripts/capture-machine.sh" "$ROOT/scripts/restore-machine.sh"
for helper in machine-filter.py merge-kde-config.py; do
    python3 -c 'import pathlib, sys; path = pathlib.Path(sys.argv[1]); compile(path.read_text(), str(path), "exec")' \
        "$ROOT/scripts/$helper"
done

# Hardware rules hold back packages, units, and files for absent hardware.
rules="$ROOT/machine/hardware-rules.tsv"
kept=$(printf '%s\n' nvidia-utils mesa intel-ucode amd-ucode thermald.service \
    /etc/docker/daemon.json /etc/laptop-battery-life.conf evdi-dkms python-pytorch-opt-cuda \
    | python3 "$ROOT/scripts/machine-filter.py" "$rules" intel-cpu,laptop)
[[ $kept == $'mesa\nintel-ucode\nthermald.service\n/etc/laptop-battery-life.conf' ]]
skipped=$(printf '%s\n' nvidia-utils evdi-dkms mesa \
    | python3 "$ROOT/scripts/machine-filter.py" "$rules" nvidia,intel-cpu --skipped)
[[ $skipped == $'evdi-dkms\tmanual' ]]

# KDE settings merge key by key and keep everything the snapshot does not name.
target="$TEST_ROOT/kwinrc"
snapshot="$TEST_ROOT/snapshot"
printf '%s\n' '[org.kde.kdecoration2]' 'library=org.kde.klassy' 'BorderSize=Tiny' '' \
    '[Compositing]' 'LatencyPolicy=Low' >"$target"
printf '%s\n' '[org.kde.kdecoration2]' 'BorderSize=Normal' '' \
    '[NightColor]' 'Active=true' >"$snapshot"
[[ $(python3 "$ROOT/scripts/merge-kde-config.py" "$snapshot" "$target") == changed ]]
grep -Fqx 'library=org.kde.klassy' "$target"
grep -Fqx 'BorderSize=Normal' "$target"
if grep -Fqx 'BorderSize=Tiny' "$target"; then exit 1; fi
grep -Fqx 'LatencyPolicy=Low' "$target"
grep -Fqx '[NightColor]' "$target"
[[ $(python3 "$ROOT/scripts/merge-kde-config.py" "$snapshot" "$target") == unchanged ]]

# Boot and repository files are compared only; restore never installs them.
if grep -n 'etc-reference' "$ROOT/scripts/restore-machine.sh" | grep -Eq '(install -|cp -a|merge-kde-config)'; then
    printf 'restore-machine.sh must not install files from etc-reference.\n' >&2
    exit 1
fi

printf 'Machine snapshot tests passed.\n'
