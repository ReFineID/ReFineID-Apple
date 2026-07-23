#!/usr/bin/env bash
#
# Archive inspection.
#
# Usage: Scripts/inspect-archive.sh /path/to/ReFineID.xcarchive

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "  ok: $*"; }

ARCHIVE="${1:?usage: inspect-archive.sh <path to .xcarchive>}"
APP="$ARCHIVE/Products/Applications/ReFineID.app"
APPEX="$APP/Contents/PlugIns/ReFineIDTokenExtension.appex"

[ -d "$APP" ] || fail "expected exactly $APP"
[ -d "$APPEX" ] || fail "embedded extension missing: $APPEX"

# --- Exactly one application, exactly one plug-in -------------------------
APP_COUNT=$(find "$ARCHIVE/Products" -maxdepth 2 -name "*.app" | wc -l | tr -d ' ')
[ "$APP_COUNT" = "1" ] || fail "expected 1 .app in archive, found $APP_COUNT"
PLUGIN_COUNT=$(find "$APP/Contents/PlugIns" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
[ "$PLUGIN_COUNT" = "1" ] || fail "expected 1 plug-in, found $PLUGIN_COUNT"
note "one app, one embedded extension"

# --- No unexpected executable code ----------------------------------------
# The only Mach-O files permitted are the two target binaries. Helper tools,
# daemons, dylibs, frameworks, and Rust artifacts are all v1.0 exclusions.
UNEXPECTED_MACHO=$(find "$APP" -type f ! -path "$APP/Contents/MacOS/ReFineID" \
    ! -path "$APPEX/Contents/MacOS/ReFineIDTokenExtension" \
    -exec sh -c 'file -b "$1" | grep -q "Mach-O" && echo "$1"' _ {} \;)
[ -z "$UNEXPECTED_MACHO" ] || fail "unexpected Mach-O files:
$UNEXPECTED_MACHO"
for forbidden in dylib framework so a; do
    HITS=$(find "$APP" -name "*.${forbidden}" | head -5)
    [ -z "$HITS" ] || fail "forbidden *.${forbidden} content:
$HITS"
done
note "no unexpected executables, libraries, or frameworks"

# --- Declared architectures ------------------------------------------------
for BIN in "$APP/Contents/MacOS/ReFineID" "$APPEX/Contents/MacOS/ReFineIDTokenExtension"; do
    ARCHS=$(lipo -archs "$BIN" | tr ' ' '\n' | sort | tr '\n' ' ')
    [ "$ARCHS" = "arm64 x86_64 " ] || fail "$BIN architectures: '$ARCHS' (expected arm64 x86_64)"
done
note "both binaries are arm64 + x86_64"

# --- Entitlements ----------------------------------------------------------
# Both binaries: app-sandbox and smartcard must be present; anything outside
# the allowlist fails. Signing adds Apple-managed identifier keys; those are
# expected.
ALLOWED='^(com\.apple\.security\.app-sandbox|com\.apple\.security\.smartcard|com\.apple\.application-identifier|com\.apple\.developer\.team-identifier|com\.apple\.security\.get-task-allow)$'
for BIN in "$APP" "$APPEX"; do
    ENT_KEYS=$(codesign -d --entitlements - --xml "$BIN" 2>/dev/null \
        | plutil -convert json -o - - | plutil -convert json - -o - 2>/dev/null \
        | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).keys()))')
    echo "$ENT_KEYS" | grep -qx "com.apple.security.app-sandbox" \
        || fail "$BIN: missing app-sandbox entitlement"
    echo "$ENT_KEYS" | grep -qx "com.apple.security.smartcard" \
        || fail "$BIN: missing smartcard entitlement"
    STRAY=$(echo "$ENT_KEYS" | grep -vE "$ALLOWED" || true)
    [ -z "$STRAY" ] || fail "$BIN: unreviewed entitlements:
$STRAY"
done
note "entitlements match the reviewed allowlist"

# --- Same team signs app and extension ------------------------------------
TEAM_APP=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
TEAM_EXT=$(codesign -dv "$APPEX" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ -n "$TEAM_APP" ] && [ "$TEAM_APP" = "$TEAM_EXT" ] \
    || fail "team mismatch: app '$TEAM_APP' vs extension '$TEAM_EXT'"
note "app and extension signed by the same team ($TEAM_APP)"

# --- Versions agree --------------------------------------------------------
V_APP=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
V_EXT=$(plutil -extract CFBundleShortVersionString raw "$APPEX/Contents/Info.plist")
[ "$V_APP" = "$V_EXT" ] || fail "version mismatch: app $V_APP vs extension $V_EXT"
note "app and extension are both version $V_APP"

# --- Privacy manifest present ----------------------------------------------
[ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ] \
    || fail "missing PrivacyInfo.xcprivacy in app resources"
note "privacy manifest present"

# --- No quarantine attributes ----------------------------------------------
QUARANTINED=$(xattr -rl "$APP" 2>/dev/null | grep "com.apple.quarantine" | head -5 || true)
[ -z "$QUARANTINED" ] || fail "quarantined files in archive:
$QUARANTINED"
note "no quarantine attributes"

# --- Signature validity -----------------------------------------------------
codesign --verify --deep --strict "$APP" || fail "codesign verification failed"
note "codesign verifies (deep, strict)"

echo "PASS: $ARCHIVE"
