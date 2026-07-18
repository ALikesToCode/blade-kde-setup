#!/usr/bin/env bash

# Read-only prerequisite and installation check.

set -u

failures=0
warnings=0

ok() { printf '  [ok] %s\n' "$*"; }
warn() { printf '  [--] %s\n' "$*"; warnings=$((warnings + 1)); }
bad() { printf '  [!!] %s\n' "$*"; failures=$((failures + 1)); }

printf 'Blade KDE doctor\n\nCommands\n'
for command in pacman kwriteconfig6 plasma-apply-lookandfeel qdbus6 konsole mpv git; do
    if command -v "$command" >/dev/null 2>&1; then
        ok "$command"
    else
        bad "$command is missing"
    fi
done

for command in yay klassy-settings reflector node pnpm wrangler openwiki officecli uv \
    code-review-graph; do
    if command -v "$command" >/dev/null 2>&1; then
        ok "$command"
    else
        warn "$command is optional or not installed yet"
    fi
done

printf '\nCodex skills\n'
for skill in officecli caveman cavecrew ask-matt tdd hallmark ecc-guide \
    karpathy-guidelines emil-design-eng; do
    if [[ -f $HOME/.agents/skills/$skill/SKILL.md ]]; then
        ok "$skill"
    else
        warn "$skill is not installed in ~/.agents/skills"
    fi
done

if codex mcp get code-review-graph --json >/dev/null 2>&1; then
    ok 'code-review-graph MCP'
else
    warn 'code-review-graph MCP is not registered with Codex'
fi
agency_agent_count=$(find "$HOME/.codex/agents" -maxdepth 1 -type f -name '*.toml' \
    2>/dev/null | wc -l)
if ((agency_agent_count >= 263)); then
    ok "$agency_agent_count Codex custom agents"
else
    warn "only $agency_agent_count Codex custom agents are installed"
fi
if command -v qmllint6 >/dev/null 2>&1 || command -v qmllint >/dev/null 2>&1; then
    ok 'QML validator'
else
    warn 'qmllint is optional or not installed yet'
fi

printf '\nUser assets\n'
declare -a assets=(
    "$HOME/.local/share/color-schemes/ArtixDarkRounded.colors"
    "$HOME/.local/share/plasma/desktoptheme/artix-dark-rounded/metadata.json"
    "$HOME/.local/share/icons/candy-icons/index.theme"
    "$HOME/.local/share/konsole/Artix Dark Rounded.profile"
    "$HOME/.local/share/klassy/Artix_Dark_Rounded.klpw"
    "$HOME/.local/share/wallpapers/BladeKDE/desktop/desktop-16x10-3840x2400.png"
    "$HOME/.local/share/blade-kde/branding/launcher/a-candy-icon.png"
)
for asset in "${assets[@]}"; do
    if [[ -e $asset ]]; then ok "${asset/#$HOME/~}"; else warn "missing: ${asset/#$HOME/~}"; fi
done

printf '\nSession health\n'
if command -v systemctl >/dev/null 2>&1 && command -v pacman >/dev/null 2>&1; then
    kwin_version=$(pacman -Q kwin 2>/dev/null | awk '{print $2}')
    kwin_package_dir="/var/lib/pacman/local/kwin-${kwin_version:-missing}"
    kwin_started=$(systemctl --user show plasma-kwin_wayland.service \
        --property=ExecMainStartTimestamp --value 2>/dev/null)
    if [[ -n $kwin_started && -d $kwin_package_dir ]] \
       && kwin_started_epoch=$(date -d "$kwin_started" +%s 2>/dev/null) \
       && kwin_installed_epoch=$(stat -c %Z "$kwin_package_dir" 2>/dev/null); then
        if ((kwin_installed_epoch > kwin_started_epoch)); then
            warn 'KWin was upgraded after this Wayland session started; log out or reboot before restarting plasmashell'
        else
            ok 'running KWin matches the installed session generation'
        fi
    else
        warn 'could not compare the running KWin session with the installed package'
    fi
else
    warn 'systemd/pacman session freshness check is unavailable'
fi

printf '\nSystem settings\n'
if [[ -r /etc/pacman.conf ]] && grep -Eq '^[[:space:]]*ParallelDownloads[[:space:]]*=[[:space:]]*15' /etc/pacman.conf; then
    ok 'Pacman ParallelDownloads = 15'
else
    warn 'Pacman parallel download tuning is not installed'
fi
if systemctl is-enabled reflector.timer >/dev/null 2>&1 \
   || [[ -L /etc/systemd/system/timers.target.wants/reflector.timer ]]; then
    ok 'Reflector timer is enabled'
else
    warn 'Reflector timer is not enabled'
fi
if [[ -r /etc/sddm.conf.d/zz-artix-qylock.conf ]]; then
    ok 'Artix Material You SDDM configuration'
else
    warn 'SDDM login theme is not installed system-wide'
fi

printf '\nResult: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
((failures == 0))
