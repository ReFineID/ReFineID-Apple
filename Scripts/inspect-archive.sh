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
# The CryptoTokenKit pair: one extension mints the token, the other exists
# only to declare the AID that ctkd polls contactless cards with. Two roles,
# two appexes -- see Config/TokenExtension-Info.plist.
APPEX="$APP/Contents/PlugIns/ReFineIDTokenExtension.appex"
APPEX_DISCOVERY="$APP/Contents/PlugIns/ReFineIDDiscoveryExtension.appex"

[ -d "$APP" ] || fail "expected exactly $APP"
[ -d "$APPEX" ] || fail "embedded extension missing: $APPEX"
[ -d "$APPEX_DISCOVERY" ] || fail "embedded extension missing: $APPEX_DISCOVERY"

# --- Exactly one application, exactly two plug-ins ------------------------
APP_COUNT=$(find "$ARCHIVE/Products" -maxdepth 2 -name "*.app" | wc -l | tr -d ' ')
[ "$APP_COUNT" = "1" ] || fail "expected 1 .app in archive, found $APP_COUNT"
PLUGIN_COUNT=$(find "$APP/Contents/PlugIns" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
[ "$PLUGIN_COUNT" = "2" ] || fail "expected 2 plug-ins, found $PLUGIN_COUNT"
note "one app, two embedded extensions"

# --- No unexpected executable code ----------------------------------------
# The only Mach-O files permitted are the three target binaries. Helper tools,
# daemons, dylibs, frameworks, and Rust artifacts are all v1.0 exclusions.
UNEXPECTED_MACHO=$(find "$APP" -type f ! -path "$APP/Contents/MacOS/ReFineID" \
    ! -path "$APPEX/Contents/MacOS/ReFineIDTokenExtension" \
    ! -path "$APPEX_DISCOVERY/Contents/MacOS/ReFineIDDiscoveryExtension" \
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
for BIN in "$APP/Contents/MacOS/ReFineID" "$APPEX/Contents/MacOS/ReFineIDTokenExtension" \
           "$APPEX_DISCOVERY/Contents/MacOS/ReFineIDDiscoveryExtension"; do
    ARCHS=$(lipo -archs "$BIN" | tr ' ' '\n' | sort | tr '\n' ' ')
    [ "$ARCHS" = "arm64 x86_64 " ] || fail "$BIN architectures: '$ARCHS' (expected arm64 x86_64)"
done
note "all binaries are arm64 + x86_64"

# --- Entitlements ----------------------------------------------------------
# Every binary: app-sandbox and smartcard must be present; anything outside
# the allowlist fails. Signing adds Apple-managed identifier keys; those are
# expected.
ALLOWED='^(com\.apple\.security\.app-sandbox|com\.apple\.security\.smartcard|com\.apple\.application-identifier|com\.apple\.developer\.team-identifier|com\.apple\.security\.get-task-allow)$'
for BIN in "$APP" "$APPEX" "$APPEX_DISCOVERY"; do
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

# --- Same team signs app and extensions -----------------------------------
TEAM_APP=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ -n "$TEAM_APP" ] || fail "could not read the app's team identifier"
for BIN in "$APPEX" "$APPEX_DISCOVERY"; do
    TEAM_EXT=$(codesign -dv "$BIN" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [ "$TEAM_APP" = "$TEAM_EXT" ] \
        || fail "team mismatch: app '$TEAM_APP' vs $BIN '$TEAM_EXT'"
done
note "app and both extensions signed by the same team ($TEAM_APP)"

# --- Versions agree --------------------------------------------------------
V_APP=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
for BIN in "$APPEX" "$APPEX_DISCOVERY"; do
    V_EXT=$(plutil -extract CFBundleShortVersionString raw "$BIN/Contents/Info.plist")
    [ "$V_APP" = "$V_EXT" ] || fail "version mismatch: app $V_APP vs $BIN $V_EXT"
done
note "app and both extensions are version $V_APP"

# --- The AID lives on the discovery extension only -------------------------
# ctkd polls with the AID an extension declares, but a driver that declares
# one stops being invoked for the app's own slot. Splitting the roles is what
# makes system-Safari login work; an archive that merges them is broken.
declares_aid() {
    plutil -convert json -o - "$1/Contents/Info.plist" | python3 -c '
import json, sys
attrs = json.load(sys.stdin).get("NSExtension", {}).get("NSExtensionAttributes", {})
sys.exit(0 if "com.apple.ctk.aid" in attrs else 1)'
}
declares_aid "$APPEX_DISCOVERY" \
    || fail "discovery extension declares no com.apple.ctk.aid; no card is ever polled"
! declares_aid "$APPEX" \
    || fail "token extension declares com.apple.ctk.aid; the token will never be minted"
note "AID declared by the discovery extension only"

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
