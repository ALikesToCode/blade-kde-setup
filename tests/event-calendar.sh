#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install-event-calendar.sh"
PATCH_FILE="$ROOT/extras/eventcalendar/blade-material.patch"
CHECKSUM_FILE="$ROOT/extras/eventcalendar/upstream.sha256"
SOURCE_DIR=${EVENTCALENDAR_SOURCE:-$HOME/github/plasma-applet-eventcalendar}
STAGING_DIR=$(mktemp -d)

cleanup() {
	rm -rf -- "$STAGING_DIR"
}
trap cleanup EXIT

bash -n "$INSTALLER"
[[ -s $PATCH_FILE ]]
[[ -s $CHECKSUM_FILE ]]
grep -Fq 'org.kde.plasma.eventcalendar' "$INSTALLER"
grep -Fq 'c8f308dcb6c036def727c9d2da6eeb8dc04bdf5b' "$INSTALLER"
grep -Fq 'BladeMaterial.qml' "$PATCH_FILE"
grep -Fq 'X-Plasma-API-Minimum-Version' "$INSTALLER"
grep -Fq 'sha256sum -c' "$INSTALLER"
"$INSTALLER" --dry-run >/dev/null

cp -a -- "$SOURCE_DIR/package" "$STAGING_DIR/package"
patch --batch --forward -d "$STAGING_DIR" -p1 < "$PATCH_FILE" >/dev/null
node - "$STAGING_DIR/package/contents/ui/lib/GoogleOAuthConfig.js" <<'NODE'
const assert = require('assert')
const config = require(process.argv[2])
const bundledId = '352447874752-sej1ldpd6piqgovtpog0dr91tb4sq5q3.apps.googleusercontent.com'

assert.strictEqual(config.authConfigurationError(bundledId, '', bundledId), '')
assert.match(config.builtInClientUnavailableMessage, /enabled with PKCE/)
NODE
grep -Fq 'Use bundled Google OAuth client (PKCE)' \
	"$STAGING_DIR/package/contents/ui/config/ConfigGoogleCalendar.qml"

printf 'event-calendar checks passed\n'
