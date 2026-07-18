#!/usr/bin/env bash

# Install the pinned Blade command-line tools and Agent Skills for Codex.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=0
SKILLS_HOME=${AGENT_SKILLS_HOME:-$HOME/.agents/skills}
CODEX_AGENTS_HOME=${CODEX_AGENTS_HOME:-$HOME/.codex/agents}
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/$(date +%Y%m%d-%H%M%S)/codex-tools"
TEMP_ROOT=

usage() {
    cat <<'EOF'
Usage: ./scripts/install-codex-tools.sh [--dry-run]

Installs pinned global CLI tools, the OfficeCLI binary, and the Blade Codex
skill collection. Existing skill directories and binaries are backed up before
replacement.
EOF
}

while (($#)); do
    case $1 in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'install-codex-tools: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

info() { printf '  • %s\n' "$*"; }
die() { printf 'install-codex-tools: %s\n' "$*" >&2; exit 1; }
print_command() {
    local arg
    printf '  $'
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
}
run() {
    if ((DRY_RUN)); then print_command "$@"; else "$@"; fi
}
cleanup() {
    [[ -z ${TEMP_ROOT:-} ]] || rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

for command in git curl sha256sum node npm; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required"
done

install_openwiki() {
    local npm_bin package package_name expected_version package_root package_json installed_version
    npm_bin=$(command -v npm)
    while IFS= read -r package; do
        [[ -n $package && $package != \#* ]] || continue
        package_name=${package%@*}
        expected_version=${package##*@}
        package_root="$($npm_bin root --global)/$package_name"
        package_json="$package_root/package.json"
        installed_version=
        if [[ -r $package_json ]]; then
            installed_version=$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' \
                "$package_json" | head -n 1)
        fi
        if [[ $installed_version == "$expected_version" ]] \
            && OPENWIKI_PACKAGE_ROOT="$package_root" node -e '
                const Database = require(process.env.OPENWIKI_PACKAGE_ROOT +
                    "/node_modules/better-sqlite3");
                const database = new Database(":memory:");
                database.prepare("select 1").get();
                database.close();
            ' >/dev/null 2>&1; then
            info "Unchanged: $package"
        else
            run sudo "$npm_bin" install --global --no-audit --no-fund \
                --allow-scripts=better-sqlite3 "$package"
        fi
    done < "$ROOT/packages/npm-global.txt"
}

install_officecli() {
    local asset checksum url download target staged actual
    case "$(uname -s):$(uname -m)" in
        Linux:x86_64)
            asset=officecli-linux-x64
            checksum=c784d89fdadfa3c6adc70b6f74bff7a6a04f7cc2b105a764369e266cca885b2b
            ;;
        Linux:aarch64|Linux:arm64)
            asset=officecli-linux-arm64
            checksum=2c43eec01356cf29f67e7ac0ca4ac51ccd8b4cf49e2a184b0201f1556403c601
            ;;
        *) die "OfficeCLI v1.0.138 is not pinned for $(uname -s) $(uname -m)" ;;
    esac
    url="https://github.com/iOfficeAI/OfficeCLI/releases/download/v1.0.138/$asset"
    target="$HOME/.local/bin/officecli"

    if [[ -x $target ]] && [[ $($target --version 2>/dev/null || true) == *1.0.138* ]]; then
        actual=$(sha256sum "$target" | awk '{print $1}')
        if [[ $actual == "$checksum" ]]; then
            info 'Unchanged: officecli v1.0.138'
            return
        fi
    fi
    if ((DRY_RUN)); then
        print_command curl -fL --retry 3 --connect-timeout 10 -o /tmp/officecli-v1.0.138 "$url"
        printf '  verify sha256 %s\n' "$checksum"
        print_command install -m 0755 /tmp/officecli-v1.0.138 "$target"
        return
    fi

    download="$TEMP_ROOT/officecli-v1.0.138"
    curl -fL --retry 3 --connect-timeout 10 -o "$download" "$url"
    actual=$(sha256sum "$download" | awk '{print $1}')
    [[ $actual == "$checksum" ]] || die "OfficeCLI checksum mismatch: $actual"
    mkdir -p -- "$(dirname -- "$target")"
    if [[ -e $target || -L $target ]]; then
        mkdir -p -- "$BACKUP_ROOT/bin"
        mv -- "$target" "$BACKUP_ROOT/bin/officecli"
    fi
    staged="$target.new.$$"
    install -m 0755 -- "$download" "$staged"
    mv -- "$staged" "$target"
    info 'Installed officecli v1.0.138 (checksum verified)'
}

declare -A REPOSITORIES=()

fetch_repository() {
    local repo=$1 ref=$2 key="$1@$2" checkout
    if [[ -n ${REPOSITORIES[$key]:-} ]]; then
        return
    fi
    checkout="$TEMP_ROOT/repos/${repo//\//-}"
    mkdir -p -- "$checkout"
    git -C "$checkout" init -q
    git -C "$checkout" remote add origin "https://github.com/$repo.git"
    git -C "$checkout" fetch -q --depth=1 origin "$ref"
    git -C "$checkout" checkout -q --detach FETCH_HEAD
    [[ $(git -C "$checkout" rev-parse HEAD) == "$ref" ]] \
        || die "repository revision mismatch for $repo"
    REPOSITORIES[$key]=$checkout
}

install_skill_tree() {
    local source=$1 name=$2 target="$SKILLS_HOME/$2" staged backup source_is_file=0
    if [[ -f $source && $(basename -- "$source") == SKILL.md ]]; then
        source_is_file=1
    elif [[ ! -f $source/SKILL.md ]]; then
        die "missing SKILL.md for $name"
    fi
    if ((source_is_file)) && [[ -f $target/SKILL.md ]] \
        && cmp -s -- "$source" "$target/SKILL.md" \
        && [[ -z $(find "$target" -mindepth 1 ! -name SKILL.md -print -quit) ]]; then
        info "Unchanged Codex skill: $name"
        return
    elif ((!source_is_file)) && [[ -d $target ]] \
        && diff -qr --no-dereference "$source" "$target" >/dev/null 2>&1; then
        info "Unchanged Codex skill: $name"
        return
    fi
    if ((DRY_RUN)); then
        if [[ -e $target || -L $target ]]; then
            printf '  backup %q -> %q\n' "$target" "$BACKUP_ROOT/skills/$name"
        fi
        printf '  install pinned Codex skill %s -> %q\n' "$name" "$target"
        return
    fi

    mkdir -p -- "$SKILLS_HOME"
    if [[ -e $target || -L $target ]]; then
        backup="$BACKUP_ROOT/skills/$name"
        mkdir -p -- "$(dirname -- "$backup")"
        mv -- "$target" "$backup"
    fi
    staged="$SKILLS_HOME/.${name}.new.$$"
    mkdir -p -- "$staged"
    if ((source_is_file)); then
        install -m 0644 -- "$source" "$staged/SKILL.md"
    else
        cp -a -- "$source/." "$staged/"
    fi
    mv -- "$staged" "$target"
    info "Installed Codex skill: $name"
}

install_skills() {
    local repo ref source_path name checkout skill_source skill_name
    if ((DRY_RUN)); then
        while IFS='|' read -r repo ref source_path name; do
            [[ -n $repo && $repo != \#* ]] || continue
            printf '  fetch %s at %s\n' "$repo" "$ref"
            if [[ $name == '*' ]]; then
                printf '  install every pinned Codex skill below %s/%s\n' "$repo" "$source_path"
            else
                printf '  install pinned Codex skill %s -> %q\n' "$name" "$SKILLS_HOME/$name"
            fi
        done < "$ROOT/packages/codex-skills.lock"
        return
    fi

    while IFS='|' read -r repo ref source_path name; do
        [[ -n $repo && $repo != \#* ]] || continue
        [[ $name != */* && -n $name ]] || die "invalid skill name in lock file: $name"
        fetch_repository "$repo" "$ref"
        checkout=${REPOSITORIES["$repo@$ref"]}
        if [[ $name == '*' ]]; then
            while IFS= read -r -d '' skill_source; do
                skill_name=$(basename -- "$skill_source")
                install_skill_tree "$skill_source" "$skill_name"
            done < <(find "$checkout/$source_path" -mindepth 1 -maxdepth 1 -type d \
                -exec test -f '{}/SKILL.md' \; -print0 | sort -z)
        else
            install_skill_tree "$checkout/$source_path" "$name"
        fi
    done < "$ROOT/packages/codex-skills.lock"
}

install_python_tools() {
    local package
    if ! command -v uv >/dev/null 2>&1 && ((!DRY_RUN)); then
        die 'uv is required; install the packages/pacman.txt manifest first'
    fi
    while IFS= read -r package; do
        [[ -n $package && $package != \#* ]] || continue
        if command -v code-review-graph >/dev/null 2>&1 \
            && [[ $(code-review-graph --version 2>/dev/null || true) == *"${package##*==}"* ]]; then
            info "Unchanged: $package"
        else
            run uv tool install --force "$package"
        fi
    done < "$ROOT/packages/python-tools.lock"
}

configure_code_review_graph() {
    command -v codex >/dev/null 2>&1 || die 'codex is required to register code-review-graph'
    if codex mcp get code-review-graph --json >/dev/null 2>&1; then
        info 'Unchanged Codex MCP: code-review-graph'
    else
        run codex mcp add code-review-graph -- code-review-graph serve
    fi

    if ((DRY_RUN)); then
        print_command code-review-graph install --platform codex \
            --repo /tmp/blade-code-review-graph --no-skills --no-instructions --dry-run
        return
    fi
    local probe="$TEMP_ROOT/code-review-graph"
    mkdir -p -- "$probe"
    code-review-graph install --platform codex --repo "$probe" \
        --no-skills --no-instructions --yes
}

install_codex_agent_file() {
    local source=$1 target="$CODEX_AGENTS_HOME/$(basename -- "$1")" backup
    if [[ -f $target ]] && cmp -s -- "$source" "$target"; then
        return
    fi
    if ((DRY_RUN)); then
        printf '  install Codex custom agent %s -> %q\n' "$(basename -- "$source")" "$target"
        return
    fi
    mkdir -p -- "$CODEX_AGENTS_HOME"
    if [[ -e $target || -L $target ]]; then
        backup="$BACKUP_ROOT/agents/$(basename -- "$target")"
        mkdir -p -- "$(dirname -- "$backup")"
        mv -- "$target" "$backup"
    fi
    install -m 0644 -- "$source" "$target"
}

install_codex_agents() {
    local repo ref target checkout generated count=0
    while IFS='|' read -r repo ref target; do
        [[ -n $repo && $repo != \#* ]] || continue
        if ((DRY_RUN)); then
            printf '  fetch %s at %s\n' "$repo" "$ref"
            printf '  generate and install all %s custom agents from %s\n' "$target" "$repo"
            continue
        fi
        fetch_repository "$repo" "$ref"
        checkout=${REPOSITORIES["$repo@$ref"]}
        bash "$checkout/scripts/convert.sh" --tool "$target"
        generated="$checkout/integrations/codex/agents"
        [[ -d $generated ]] || die "Agency Codex conversion did not produce $generated"
        while IFS= read -r -d '' agent_file; do
            install_codex_agent_file "$agent_file"
            count=$((count + 1))
        done < <(find "$generated" -maxdepth 1 -type f -name '*.toml' -print0 | sort -z)
    done < "$ROOT/packages/codex-agents.lock"
    ((DRY_RUN)) || info "Installed or verified $count Agency Codex agents"
}

if ((DRY_RUN)); then
    info 'Dry run: no tools or skills will be changed.'
else
    TEMP_ROOT=$(mktemp -d /tmp/blade-codex-tools.XXXXXX)
fi

install_openwiki
install_officecli
install_skills
install_python_tools
configure_code_review_graph
install_codex_agents

if ((!DRY_RUN)) && [[ -d $BACKUP_ROOT ]]; then
    info "Previous tools backed up to ${BACKUP_ROOT/#$HOME/~}"
fi
info 'Codex tools and skills are ready. Restart Codex to load newly installed skills.'
