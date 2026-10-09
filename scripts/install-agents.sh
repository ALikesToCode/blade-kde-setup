#!/usr/bin/env bash

set -Eeuo pipefail
umask 077
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=0
ACTIVATE=0
for argument in "$@"; do
    case "$argument" in
        --dry-run) DRY_RUN=1 ;;
        --activate) ACTIVATE=1 ;;
        --help)
            printf 'Usage: %s [--dry-run] [--activate]\n' "$0"
            printf 'Install Blade Agents; --activate starts the shared code-review-graph server\n'
            printf 'and switches ~/.codex/config.toml to it with the heavy MCP servers disabled.\n'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
    esac
done

DATA_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG_ROOT=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_ROOT=${XDG_STATE_HOME:-$HOME/.local/state}
BACKUP_ROOT=${BLADE_BACKUP_ROOT:-$STATE_ROOT/blade-kde-backups/agents-$(date +%Y%m%d-%H%M%S-%N)}
RENDER_DIR=$(mktemp -d)
trap 'rm -rf -- "$RENDER_DIR"' EXIT

copy_file() {
    local source=$1 target=$2 mode=${3:-644}
    if [[ -f $target ]] && cmp -s -- "$source" "$target"; then
        return
    fi
    if ((DRY_RUN)); then
        printf 'Would install %s -> %s\n' "${source#"$ROOT"/}" "$target"
        return
    fi
    [[ ! -L $target ]] || { printf 'Refusing symlink target: %s\n' "$target" >&2; exit 1; }
    if [[ -e $target ]]; then
        local backup="$BACKUP_ROOT/${target#/}"
        [[ ! -e $backup ]] || { printf 'Backup already exists: %s\n' "$backup" >&2; exit 1; }
        mkdir -p -- "$(dirname -- "$backup")"
        cp -a -- "$target" "$backup"
    fi
    mkdir -p -- "$(dirname -- "$target")"
    install -m "$mode" -- "$source" "$target"
}

copy_file "$ROOT/bin/blade-agents" "$HOME/.local/bin/blade-agents" 755
copy_file "$ROOT/bin/blade-testlock" "$HOME/.local/bin/blade-testlock" 755
for source in "$ROOT"/lib/blade_agents/*.py; do
    copy_file "$source" "$DATA_ROOT/blade-kde/lib/blade_agents/${source##*/}"
done
copy_file "$ROOT/dotfiles/systemd/user/code-review-graph.service" \
    "$CONFIG_ROOT/systemd/user/code-review-graph.service"
# The shared server depends on agents passing repo_root, which these
# instructions require, so --agents installs them even without --user.
sed "s|__HOME__|${HOME//&/\\&}|g" "$ROOT/dotfiles/agents/AGENTS.md" >"$RENDER_DIR/AGENTS.md"
copy_file "$RENDER_DIR/AGENTS.md" "$HOME/.codex/AGENTS.md"

((ACTIVATE)) || exit 0
if ((DRY_RUN)); then
    printf 'Would start code-review-graph.service, then disable artemis, blender-lab, and\n'
    printf 'higgsfield-use-blender and point code-review-graph at it in ~/.codex/config.toml.\n'
    exit 0
fi
for executable in code-review-graph systemctl curl; do
    command -v "$executable" >/dev/null || {
        printf 'Missing %s; run ./install.sh --tools first.\n' "$executable" >&2
        exit 1
    }
done
systemctl --user daemon-reload
systemctl --user enable --now code-review-graph.service
# Switch Codex only once the server answers, or new threads start without it.
for _ in {1..30}; do
    curl -s -o /dev/null --max-time 2 http://127.0.0.1:14155/mcp && break
    sleep 1
done
curl -s -o /dev/null --max-time 2 http://127.0.0.1:14155/mcp || {
    printf 'code-review-graph.service is not answering; see journalctl --user -u code-review-graph\n' >&2
    exit 1
}
BLADE_BACKUP_ROOT="$BACKUP_ROOT" "$HOME/.local/bin/blade-agents" configure
printf 'Blade Agents is active. New Codex threads use the shared code-review-graph server;\n'
printf 'running threads keep their own MCP servers until they close.\n'
