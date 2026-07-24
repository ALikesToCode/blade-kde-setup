#!/usr/bin/env bash

# Install the Plasma 6 Event Calendar with the non-destructive Blade Material overlay.

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PATCH_FILE="$ROOT/extras/eventcalendar/blade-material.patch"
CHECKSUM_FILE="$ROOT/extras/eventcalendar/upstream.sha256"
APPLET_ID=org.kde.plasma.eventcalendar
UPSTREAM_URL=https://github.com/ALikesToCode/plasma-applet-eventcalendar.git
UPSTREAM_REF=c8f308dcb6c036def727c9d2da6eeb8dc04bdf5b
SOURCE_DIR=${EVENTCALENDAR_SOURCE:-}
DRY_RUN=0
SKIP_PYTHON_DEPS=0
STAGING_DIR=
FETCH_DIR=
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/blade-kde-backups/$(date +%Y%m%d-%H%M%S)"

usage() {
    cat <<'EOF'
Usage: ./scripts/install-event-calendar.sh [options]

Installs the pinned Plasma 6 Event Calendar package with the Blade Material
blue/green theme. A local source checkout is preferred; otherwise the pinned
upstream revision is fetched into a temporary directory.

Options:
  --source DIR         Use this Event Calendar source checkout
  --skip-python-deps   Skip optional recurring iCalendar support
  -n, --dry-run        Validate and print the plan without changing anything
  -h, --help           Show this help

Environment:
  EVENTCALENDAR_SOURCE  Same as --source
EOF
}

while (($#)); do
    case $1 in
        --source)
            shift
            (($#)) || { printf 'install-event-calendar: --source requires a directory\n' >&2; exit 2; }
            SOURCE_DIR=$1
            ;;
        --skip-python-deps) SKIP_PYTHON_DEPS=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'install-event-calendar: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

cleanup() {
    [[ -z $STAGING_DIR ]] || rm -rf -- "$STAGING_DIR"
    [[ -z $FETCH_DIR ]] || rm -rf -- "$FETCH_DIR"
}
trap cleanup EXIT

find_source() {
    local candidate
    if [[ -n $SOURCE_DIR ]]; then
        return 0
    fi
    for candidate in \
        "$HOME/github/plasma-applet-eventcalendar" \
        "$HOME/storage/github/plasma-applet-eventcalendar"; do
        if [[ -f $candidate/package/metadata.json ]]; then
            SOURCE_DIR=$candidate
            return 0
        fi
    done
}

validate_source() {
    local metadata=$SOURCE_DIR/package/metadata.json
    [[ -f $metadata ]] || {
        printf 'install-event-calendar: missing package/metadata.json below %s\n' "$SOURCE_DIR" >&2
        exit 1
    }
    [[ $(jq -r '.KPlugin.Id // ""' "$metadata") == "$APPLET_ID" ]] || {
        printf 'install-event-calendar: unexpected applet id in %s\n' "$metadata" >&2
        exit 1
    }
    [[ $(jq -r '."X-Plasma-API-Minimum-Version" // ""' "$metadata") == 6.* ]] || {
        printf 'install-event-calendar: the selected source is not a Plasma 6 package\n' >&2
        exit 1
    }
    (cd -- "$SOURCE_DIR" && sha256sum -c "$CHECKSUM_FILE" >/dev/null) || {
        printf 'install-event-calendar: source does not match the pinned, reviewed Plasma 6 revision\n' >&2
        exit 1
    }
    patch --batch --forward --dry-run -d "$SOURCE_DIR" -p1 < "$PATCH_FILE" >/dev/null
}

fetch_source() {
    FETCH_DIR=$(mktemp -d)
    SOURCE_DIR=$FETCH_DIR/source
    git init -q "$SOURCE_DIR"
    git -C "$SOURCE_DIR" remote add origin "$UPSTREAM_URL"
    git -C "$SOURCE_DIR" fetch -q --depth 1 origin "$UPSTREAM_REF"
    git -C "$SOURCE_DIR" checkout -q --detach FETCH_HEAD
}

install_python_dependencies() {
    local python_dir="${XDG_DATA_HOME:-$HOME/.local/share}/plasma_org.kde.plasma.eventcalendar/python"
    local python_path=$python_dir
    [[ -z ${PYTHONPATH:-} ]] || python_path="$python_path:$PYTHONPATH"

    if PYTHONPATH="$python_path" python3 -c 'import icalendar, recurring_ical_events' >/dev/null 2>&1; then
        printf 'Event Calendar: recurring iCalendar support is already available.\n'
        return 0
    fi
    mkdir -p -- "$python_dir"
    python3 -m pip install \
        --disable-pip-version-check \
        --no-warn-script-location \
        --upgrade \
        --target "$python_dir" \
        'icalendar>=6.1,<8' \
        'recurring-ical-events>=3.8,<4'
    PYTHONPATH="$python_path" python3 -c 'import icalendar, recurring_ical_events'
}

command -v jq >/dev/null 2>&1 || { printf 'install-event-calendar: jq is required\n' >&2; exit 1; }
command -v patch >/dev/null 2>&1 || { printf 'install-event-calendar: patch is required\n' >&2; exit 1; }
command -v kpackagetool6 >/dev/null 2>&1 || { printf 'install-event-calendar: kpackagetool6 is required\n' >&2; exit 1; }
[[ -f $PATCH_FILE ]] || { printf 'install-event-calendar: missing %s\n' "$PATCH_FILE" >&2; exit 1; }
[[ -f $CHECKSUM_FILE ]] || { printf 'install-event-calendar: missing %s\n' "$CHECKSUM_FILE" >&2; exit 1; }

find_source
if [[ -z $SOURCE_DIR ]]; then
    if ((DRY_RUN)); then
        printf 'Event Calendar plan:\n'
        printf '  fetch: %s at %s\n' "$UPSTREAM_URL" "$UPSTREAM_REF"
        printf '  overlay: %s\n' "$PATCH_FILE"
        printf '  install: %s through kpackagetool6\n' "$APPLET_ID"
        exit 0
    fi
    fetch_source
fi

SOURCE_DIR=$(cd -- "$SOURCE_DIR" && pwd)
validate_source

printf 'Event Calendar plan:\n'
printf '  source: %s\n' "$SOURCE_DIR"
printf '  overlay: Blade Material dark cards with blue/green accents\n'
printf '  applet: %s\n' "$APPLET_ID"
if ((DRY_RUN)); then
    printf '  action: validate only\n'
    exit 0
fi

STAGING_DIR=$(mktemp -d)
cp -a -- "$SOURCE_DIR/package" "$STAGING_DIR/package"
patch --batch --forward -d "$STAGING_DIR" -p1 < "$PATCH_FILE" >/dev/null

installed_dir="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$APPLET_ID"
if [[ -d $installed_dir ]] && diff -qr --no-dereference "$STAGING_DIR/package" "$installed_dir" >/dev/null 2>&1; then
    printf 'Event Calendar: installed package is already current.\n'
elif [[ -e $installed_dir ]]; then
    backup_dir="$BACKUP_ROOT/home/${USER:-user}/.local/share/plasma/plasmoids"
    mkdir -p -- "$backup_dir"
    cp -a -- "$installed_dir" "$backup_dir/$APPLET_ID"
    printf 'Backed up the existing Event Calendar to %s\n' "$backup_dir/$APPLET_ID"
    kpackagetool6 --type Plasma/Applet --upgrade "$STAGING_DIR/package"
else
    kpackagetool6 --type Plasma/Applet --install "$STAGING_DIR/package"
fi

if ((SKIP_PYTHON_DEPS == 0)); then
    install_python_dependencies
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null
fi

printf 'Event Calendar %s with the Blade Material overlay is installed.\n' \
    "$(jq -r '.KPlugin.Version' "$SOURCE_DIR/package/metadata.json")"
