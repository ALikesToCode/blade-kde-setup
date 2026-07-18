#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$ROOT/install.sh" "$ROOT/bin/update-all-packages" "$ROOT/bin/updateall" \
    "$ROOT/scripts/apply-kde.sh" "$ROOT/scripts/apply-wallpapers.sh" \
    "$ROOT/scripts/apply-panels.sh" "$ROOT/scripts/doctor.sh"
bash -n "$ROOT/dotfiles/apps/zen/zen-browser" "$ROOT/dotfiles/apps/zed/zeditor" \
    "$ROOT/scripts/verify-app-launchers.sh"

python3 -m json.tool "$ROOT/dotfiles/yay/config.json" >/dev/null
python3 -m json.tool \
    "$ROOT/kde/look-and-feel/org.mysterious.artixdarkrounded.desktop/metadata.json" >/dev/null
python3 -m json.tool "$ROOT/kde/desktoptheme/artix-dark-rounded/metadata.json" >/dev/null
(cd "$ROOT" && sha256sum -c assets/wallpapers/SHA256SUMS >/dev/null)
(cd "$ROOT/assets/branding/launcher" && sha256sum -c SHA256SUMS >/dev/null)
if command -v node >/dev/null 2>&1; then
    node --check "$ROOT/kde/plasma/blade-panels.js"
fi

required=(
    LICENSE
    README.md
    packages/pacman.txt
    kde/color-schemes/ArtixDarkRounded.colors
    kde/look-and-feel/org.mysterious.artixdarkrounded.desktop/metadata.json
    kde/desktoptheme/artix-dark-rounded/metadata.json
    kde/desktoptheme/artix-dark-rounded/colors
    kde/sddm/artix-material-you/Main.qml
    assets/icons/candy-icons/index.theme
    assets/branding/launcher/a-candy-icon.png
    assets/branding/launcher/hicolor/64x64/apps/mysterious-a.png
    assets/wallpapers/desktop/desktop-16x10-3840x2400.png
    assets/wallpapers/desktop/desktop-ultrawide-3440x1440.png
    assets/wallpapers/login/login-16x10-3840x2400.png
    assets/wallpapers/login/login-ultrawide-3440x1440.png
    dotfiles/apps/zen/zen-browser
    dotfiles/apps/zen/zen.desktop
    dotfiles/apps/zen/user.js
    dotfiles/apps/antigravity/antigravity-flags.conf
    dotfiles/apps/zed/zeditor
    dotfiles/apps/zed/dev.zed.Zed.desktop
    dotfiles/agents/AGENTS.md
    dotfiles/nvim/init.lua
    kde/plasma/blade-panels.js
    scripts/apply-panels.sh
)
for path in "${required[@]}"; do
    [[ -e $ROOT/$path ]] || { printf 'Missing required file: %s\n' "$path" >&2; exit 1; }
done

grep -Fqx "    alias vi='nvim'" "$ROOT/dotfiles/bash/bashrc"
grep -Fqx "    alias vim='nvim'" "$ROOT/dotfiles/bash/bashrc"
rg -q '^### Atomic and independent commits$' "$ROOT/dotfiles/agents/AGENTS.md"
rg -q '^### Destructive actions require approval$' "$ROOT/dotfiles/agents/AGENTS.md"

if rg -n --hidden --glob '!.git/**' \
    '(sk-navy-[A-Za-z0-9_-]+|gh[pousr]_[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' \
    "$ROOT"; then
    printf 'Potential secret found.\n' >&2
    exit 1
fi

if rg -n --hidden --glob '!.git/**' '/home/mysterious|__HOME__.*__HOME__' "$ROOT" \
    --glob '!**/tests/smoke.sh'; then
    printf 'A machine-specific home path remains in the repository.\n' >&2
    exit 1
fi

"$ROOT/install.sh" --dry-run --all >/dev/null

printf 'Smoke tests passed.\n'
