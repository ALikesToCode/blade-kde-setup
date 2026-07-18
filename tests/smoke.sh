#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$ROOT/install.sh" "$ROOT/bin/update-all-packages" "$ROOT/bin/updateall" \
    "$ROOT/scripts/apply-kde.sh" "$ROOT/scripts/apply-wallpapers.sh" "$ROOT/scripts/doctor.sh"
bash -n "$ROOT/dotfiles/apps/zen/zen-browser" "$ROOT/dotfiles/apps/zed/zeditor" \
    "$ROOT/scripts/verify-app-launchers.sh"

python3 -m json.tool "$ROOT/dotfiles/yay/config.json" >/dev/null
python3 -m json.tool \
    "$ROOT/kde/look-and-feel/org.mysterious.artixdarkrounded.desktop/metadata.json" >/dev/null
(cd "$ROOT" && sha256sum -c assets/wallpapers/SHA256SUMS >/dev/null)

required=(
    LICENSE
    README.md
    packages/pacman.txt
    kde/color-schemes/ArtixDarkRounded.colors
    kde/look-and-feel/org.mysterious.artixdarkrounded.desktop/metadata.json
    kde/sddm/artix-material-you/Main.qml
    assets/icons/candy-icons/index.theme
    assets/wallpapers/desktop/desktop-16x10-3840x2400.png
    assets/wallpapers/desktop/desktop-ultrawide-3440x1440.png
    assets/wallpapers/login/login-16x10-3840x2400.png
    assets/wallpapers/login/login-ultrawide-3440x1440.png
    dotfiles/apps/zen/zen-browser
    dotfiles/apps/zen/zen.desktop
    dotfiles/apps/antigravity/antigravity-flags.conf
    dotfiles/apps/zed/zeditor
    dotfiles/apps/zed/dev.zed.Zed.desktop
)
for path in "${required[@]}"; do
    [[ -e $ROOT/$path ]] || { printf 'Missing required file: %s\n' "$path" >&2; exit 1; }
done

if rg -n --hidden --glob '!.git/**' \
    '(sk-navy-[A-Za-z0-9_-]+|gh[pousr]_[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' \
    "$ROOT"; then
    printf 'Potential secret found.\n' >&2
    exit 1
fi

if rg -n --hidden --glob '!.git/**' '/home/mysterious|__HOME__.*__HOME__' "$ROOT" \
    --glob '!tests/smoke.sh'; then
    printf 'A machine-specific home path remains in the repository.\n' >&2
    exit 1
fi

"$ROOT/install.sh" --dry-run --all >/dev/null

printf 'Smoke tests passed.\n'
