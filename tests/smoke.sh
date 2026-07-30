#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$ROOT/install.sh" "$ROOT/bin/update-all-packages" "$ROOT/bin/updateall" \
    "$ROOT/bin/aria2-daemon" "$ROOT/bin/ariang" \
    "$ROOT/scripts/apply-kde.sh" "$ROOT/scripts/apply-wallpapers.sh" \
    "$ROOT/scripts/apply-panels.sh" "$ROOT/scripts/doctor.sh" \
    "$ROOT/scripts/install-event-calendar.sh"
bash -n "$ROOT/scripts/install-codex-tools.sh" "$ROOT/scripts/install-ariang.sh"
bash -n "$ROOT/tests/network-speed-widget.sh" "$ROOT/tests/browser-mode-isolation.sh" \
    "$ROOT/tests/browser-profile-persistence.sh" "$ROOT/tests/clipboard-bridge.sh" \
    "$ROOT/tests/aria2-daemon.sh" "$ROOT/tests/ariang.sh"
bash -n "$ROOT/dotfiles/apps/zen/zen-browser" "$ROOT/dotfiles/apps/zed/zeditor" \
    "$ROOT/scripts/verify-app-launchers.sh" "$ROOT/tests/sddm-theme.sh" \
    "$ROOT/tests/zen-window-controls.sh" "$ROOT/scripts/apply-desktop-clock.sh" \
    "$ROOT/tests/desktop-clock.sh" \
    "$ROOT/tests/event-calendar.sh"
bash -n \
    "$ROOT/extras/hardened-workspace/install.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/browser-profile.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/nested-display.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/runtime-inner.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/keyring-stack.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/self-test-inner.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/doctor.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/test-sandbox.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/uninstall.sh" \
    "$ROOT/extras/hardened-workspace/payload/home/.local/bin/cloakserve" \
    "$ROOT/extras/hardened-workspace/payload/home/.local/bin/codex-safe" \
    "$ROOT/extras/hardened-workspace/payload/home/.local/bin/codex-safe-migrate-mcp" \
    "$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-cli" \
    "$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-cloak" \
    "$ROOT/extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-safe"

python3 -m json.tool "$ROOT/dotfiles/yay/config.json" >/dev/null
python3 -m json.tool \
    "$ROOT/kde/look-and-feel/org.mysterious.artixdarkrounded.desktop/metadata.json" >/dev/null
python3 -m json.tool "$ROOT/kde/desktoptheme/artix-dark-rounded/metadata.json" >/dev/null
(cd "$ROOT" && sha256sum -c assets/wallpapers/SHA256SUMS >/dev/null)
(cd "$ROOT/assets/branding/launcher" && sha256sum -c SHA256SUMS >/dev/null)
if command -v node >/dev/null 2>&1; then
    node --check "$ROOT/kde/plasma/blade-panels.js"
    node --check \
        "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/node-playwright-preload.cjs"
fi
python3 - "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/python/sitecustomize.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(), str(path), "exec")
PY
python3 - "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/clipboard-bridge.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(), str(path), "exec")
PY
python3 - "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/nested-window-manager.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(), str(path), "exec")
PY
python3 - "$ROOT/bin/ariang-server" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(), str(path), "exec")
PY

required=(
    LICENSE
    README.md
    docs/CONFIGURATION-INVENTORY.md
    packages/pacman.txt
    packages/npm-global.txt
    packages/python-tools.lock
    packages/codex-skills.lock
    packages/codex-agents.lock
    packages/ariang.lock
    kde/color-schemes/ArtixDarkRounded.colors
    kde/look-and-feel/org.mysterious.artixdarkrounded.desktop/metadata.json
    kde/desktoptheme/artix-dark-rounded/metadata.json
    kde/desktoptheme/artix-dark-rounded/colors
    kde/sddm/artix-material-you/Main.qml
    kde/plasma/plasmoids/org.mysterious.bladeclock/metadata.json
    kde/plasma/plasmoids/org.mysterious.bladeclock/contents/ui/main.qml
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
    dotfiles/apps/zen/chrome/blade-window-controls.css
    dotfiles/apps/zen/chrome/blade-window-minimize.svg
    dotfiles/apps/zen/chrome/blade-window-maximize.svg
    dotfiles/apps/zen/chrome/blade-window-restore.svg
    dotfiles/apps/zen/chrome/blade-window-close.svg
    dotfiles/apps/antigravity/antigravity-flags.conf
    dotfiles/apps/zed/zeditor
    dotfiles/apps/zed/dev.zed.Zed.desktop
    dotfiles/agents/AGENTS.md
    dotfiles/downloads/aria2/daemon.conf
    dotfiles/systemd/user/aria2.service
    dotfiles/systemd/user/ariang.service
    dotfiles/apps/ariang/ariang.desktop
    dotfiles/nvim/init.lua
    kde/plasma/blade-panels.js
    scripts/apply-panels.sh
    scripts/install-event-calendar.sh
    extras/eventcalendar/blade-material.patch
    extras/eventcalendar/upstream.sha256
    scripts/apply-desktop-clock.sh
    scripts/install-codex-tools.sh
    scripts/install-ariang.sh
    bin/aria2-daemon
    bin/ariang
    bin/ariang-server
    extras/hardened-workspace/install.sh
    extras/hardened-workspace/cloakserve-codex-safe.patch
    extras/hardened-workspace/cloakserve-graceful-close-upgrade.patch
    extras/hardened-workspace/payload/home/.config/firejail/codex-safe.profile
    extras/hardened-workspace/payload/home/.config/codex-safe/browser-profile.sh
    extras/hardened-workspace/payload/home/.config/codex-safe/clipboard-bridge.py
    extras/hardened-workspace/payload/home/.config/codex-safe/nested-display.sh
    extras/hardened-workspace/payload/home/.config/codex-safe/nested-window-manager.py
    extras/hardened-workspace/payload/home/.config/codex-safe/runtime-inner.sh
    extras/hardened-workspace/payload/home/.config/codex-safe/keyring-stack.sh
    extras/hardened-workspace/payload/home/.local/bin/codex-safe
    extras/hardened-workspace/payload/home/.local/bin/codex-safe-migrate-mcp
    extras/hardened-workspace/payload/home/.local/bin/playwright-mcp-cloak
    tests/browser-mode-isolation.sh
    tests/browser-profile-persistence.sh
    tests/clipboard-bridge.sh
    tests/ariang.sh
)
for path in "${required[@]}"; do
    [[ -e $ROOT/$path ]] || { printf 'Missing required file: %s\n' "$path" >&2; exit 1; }
done

grep -Fqx "    alias vi='nvim'" "$ROOT/dotfiles/bash/bashrc"
grep -Fqx "    alias vim='nvim'" "$ROOT/dotfiles/bash/bashrc"
"$ROOT/tests/sddm-theme.sh" >/dev/null
"$ROOT/tests/zen-window-controls.sh" >/dev/null
"$ROOT/tests/desktop-clock.sh" >/dev/null
"$ROOT/tests/event-calendar.sh" >/dev/null
bash "$ROOT/tests/network-speed-widget.sh" >/dev/null
bash "$ROOT/tests/update-all-packages.sh" >/dev/null
bash "$ROOT/tests/browser-mode-isolation.sh" >/dev/null
bash "$ROOT/tests/browser-profile-persistence.sh" >/dev/null
bash "$ROOT/tests/clipboard-bridge.sh" >/dev/null
bash "$ROOT/tests/aria2-daemon.sh" >/dev/null
bash "$ROOT/tests/ariang.sh" >/dev/null
rg -q 'shell_environment_policy\.set\.CLOAK_CDP_ENDPOINT' \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/runtime-inner.sh"
rg -q 'mcp_servers\.playwright_safe\.env\.CLOAK_CDP_ENDPOINT' \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/runtime-inner.sh"
grep -Fq 'mcp_oauth_credentials_store="keyring"' \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/runtime-inner.sh"
grep -Fq 'shell_environment_policy.exclude=["DBUS_SESSION_BUS_ADDRESS"' \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/runtime-inner.sh"
rg -q 'blacklist \$\{HOME\}/\.local/share/codex-safe/keyring' \
    "$ROOT/extras/hardened-workspace/payload/home/.config/firejail/codex-safe.profile"
grep -Fqx 'gnome-keyring' "$ROOT/packages/pacman.txt"
rg -q 'systemctl --user mask --now gnome-keyring-daemon\.socket' \
    "$ROOT/extras/hardened-workspace/install.sh"
rg -q 'configure_playwright_server playwright_safe headless' \
    "$ROOT/extras/hardened-workspace/install.sh"
rg -q 'configure_playwright_server playwright_safe_headed headed' \
    "$ROOT/extras/hardened-workspace/install.sh"
rg -q '^### Atomic and independent commits$' "$ROOT/dotfiles/agents/AGENTS.md"
rg -q '^### Destructive actions require approval$' "$ROOT/dotfiles/agents/AGENTS.md"
rg -q '^### Skill and configuration access$' "$ROOT/dotfiles/agents/AGENTS.md"
rg -q '^### Maintainable module and file boundaries$' "$ROOT/dotfiles/agents/AGENTS.md"
rg -q '^### Repository-authored publication voice$' "$ROOT/dotfiles/agents/AGENTS.md"
grep -Fq 'Do not create or further expand a hand-written source file beyond 1,000 lines.' \
    "$ROOT/dotfiles/agents/AGENTS.md"
grep -Fq 'Do not bundle independent changes merely because they were produced during the same request or working session.' \
    "$ROOT/dotfiles/agents/AGENTS.md"
grep -Fq 'Do not narrate the prompt, working session, tools, agent workflow, model, or content-generation process.' \
    "$ROOT/dotfiles/agents/AGENTS.md"
rg -q '^### Browser mode declaration and cursor isolation$' \
    "$ROOT/dotfiles/agents/AGENTS.md"
# shellcheck disable=SC2016
grep -Fq 'Before the first browser tool call, explicitly state `Browser mode: headless` or `Browser mode: headed`' \
    "$ROOT/dotfiles/agents/AGENTS.md"
grep -Fq 'must never read, request, type, paste, or log the user'\''s credentials.' \
    "$ROOT/dotfiles/agents/AGENTS.md"
grep -Fq 'Headed always means visible:' "$ROOT/dotfiles/agents/AGENTS.md"
grep -Fqx 'xorg-server-xephyr' "$ROOT/packages/pacman.txt"
grep -Fqx 'xorg-xauth' "$ROOT/packages/pacman.txt"
grep -Fqx 'xclip' "$ROOT/packages/pacman.txt"
grep -Fq '14e10cb340a0a8e37b60f90742fe01f021035e77c8eb43b9ca98c228a3b455ef' \
    "$ROOT/extras/hardened-workspace/payload/home/.config/codex-safe/config"

[[ $(grep -Ec '^[^#].*\|.*\|.*\|.*$' "$ROOT/packages/codex-skills.lock") -eq 46 ]]
grep -Fqx 'openwiki@0.2.0' "$ROOT/packages/npm-global.txt"
grep -Fqx 'code-review-graph==2.3.7' "$ROOT/packages/python-tools.lock"
rg -q '^Nutlope/hallmark\|[0-9a-f]{40}\|skills/hallmark\|hallmark$' \
    "$ROOT/packages/codex-skills.lock"
rg -q '^affaan-m/ECC\|[0-9a-f]{40}\|skills\|\*$' \
    "$ROOT/packages/codex-skills.lock"
rg -q '^multica-ai/andrej-karpathy-skills\|[0-9a-f]{40}\|' \
    "$ROOT/packages/codex-skills.lock"
rg -q '^emilkowalski/skills\|[0-9a-f]{40}\|' \
    "$ROOT/packages/codex-skills.lock"
rg -q '^tirth8205/code-review-graph\|[0-9a-f]{40}\|' \
    "$ROOT/packages/codex-skills.lock"
rg -q '^msitarzewski/agency-agents\|[0-9a-f]{40}\|codex$' \
    "$ROOT/packages/codex-agents.lock"
grep -Fqx '@__HOME__/.codex/RTK.md' "$ROOT/dotfiles/agents/AGENTS.md"

if find "$ROOT/extras/hardened-workspace" -name '.codex-safe-verification*' -print -quit | grep -q .; then
    printf 'Verification scratch data must not be bundled.\n' >&2
    exit 1
fi

if rg -n --hidden --glob '!.git' --glob '!.git/**' \
    '(sk-navy-[A-Za-z0-9_-]+|gh[pousr]_[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' \
    "$ROOT"; then
    printf 'Potential secret found.\n' >&2
    exit 1
fi

if rg -n --hidden --glob '!.git' --glob '!.git/**' \
    '/home/mysterious|__HOME__.*__HOME__' "$ROOT" \
    --glob '!**/tests/smoke.sh'; then
    printf 'A machine-specific home path remains in the repository.\n' >&2
    exit 1
fi

"$ROOT/install.sh" --dry-run --all >/dev/null
"$ROOT/install.sh" --dry-run --hardened >/dev/null
"$ROOT/scripts/install-codex-tools.sh" --dry-run >/dev/null

printf 'Smoke tests passed.\n'
