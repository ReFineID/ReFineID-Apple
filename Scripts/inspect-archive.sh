#!/usr/bin/env bash
#
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#

# Archive inspection.
#
# Usage: Scripts/inspect-archive.sh /path/to/ReFineID.xcarchive
#
# Handles both platforms. Almost every check is the same question asked
# of a different layout, so the paths are resolved once below and the
# checks are written against those; only the architectures, the reviewed
# entitlement allowlist and the keychain-group ordering genuinely differ.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "  ok: $*"; }

ARCHIVE="${1:?usage: inspect-archive.sh <path to .xcarchive>}"
APP="$ARCHIVE/Products/Applications/ReFineID.app"
# The CryptoTokenKit pair: one extension mints the token, the other exists
# only to declare the AID that ctkd polls contactless cards with. Two roles,
# two appexes -- see Config/TokenExtension-Info.plist.
APPEX="$APP/PlugIns/ReFineIDTokenExtension.appex"
APPEX_DISCOVERY="$APP/PlugIns/ReFineIDDiscoveryExtension.appex"

[ -d "$APP" ] || fail "expected exactly $APP"

# --- Which platform this archive is ---------------------------------------
# A Mac app keeps everything under Contents/; an iOS app bundle is flat.
# Nothing else in the archive states the platform as plainly.
if [ -d "$APP/Contents" ]; then
    PLATFORM="macOS"
    APP_EXEC="$APP/Contents/MacOS/ReFineID"
    APP_PLIST="$APP/Contents/Info.plist"
    APP_RESOURCES="$APP/Contents/Resources"
    PLUGINS="$APP/Contents/PlugIns"
    APPEX="$PLUGINS/ReFineIDTokenExtension.appex"
    APPEX_DISCOVERY="$PLUGINS/ReFineIDDiscoveryExtension.appex"
    APPEX_EXEC="$APPEX/Contents/MacOS/ReFineIDTokenExtension"
    APPEX_DISCOVERY_EXEC="$APPEX_DISCOVERY/Contents/MacOS/ReFineIDDiscoveryExtension"
    APPEX_PLIST="$APPEX/Contents/Info.plist"
    APPEX_DISCOVERY_PLIST="$APPEX_DISCOVERY/Contents/Info.plist"
    EXPECTED_ARCHS="arm64 x86_64 "
    # The discovery extension is iOS-only. It exists to declare the AID
    # ctkd polls contactless cards with, and a Mac reader hands the card
    # over without one -- on macOS it could only claim a card in order to
    # refuse it, so it is not embedded there.
    HAS_DISCOVERY="no"
    # Sandbox and smart-card access, plus the keys signing adds.
    #
    # network.client is the app's alone and exists for one feature: an
    # archival signature must fetch a qualified timestamp and the
    # revocation data proving its chain. Neither extension carries it --
    # a token extension that could reach the network is a token
    # extension nobody can reason about -- so it is checked per binary
    # below rather than allowed everywhere.
    ALLOWED='^(com\.apple\.security\.app-sandbox|com\.apple\.security\.smartcard|com\.apple\.security\.network\.client|com\.apple\.security\.files\.user-selected\.read-write|com\.apple\.application-identifier|com\.apple\.developer\.team-identifier|com\.apple\.security\.get-task-allow)$'
    REQUIRED="com.apple.security.app-sandbox com.apple.security.smartcard"
else
    PLATFORM="iOS"
    APP_EXEC="$APP/ReFineID"
    APP_PLIST="$APP/Info.plist"
    APP_RESOURCES="$APP"
    PLUGINS="$APP/PlugIns"
    APPEX_EXEC="$APPEX/ReFineIDTokenExtension"
    APPEX_DISCOVERY_EXEC="$APPEX_DISCOVERY/ReFineIDDiscoveryExtension"
    APPEX_PLIST="$APPEX/Info.plist"
    APPEX_DISCOVERY_PLIST="$APPEX_DISCOVERY/Info.plist"
    EXPECTED_ARCHS="arm64 "
    HAS_DISCOVERY="yes"
    # iOS sandboxes every app without an entitlement saying so, and grants
    # smart-card access through CryptoTokenKit rather than a sandbox
    # exception. What is reviewed here instead is the shared keychain group
    # the three binaries pass the prime and the stored credentials through,
    # and the app's Core NFC tag-reading grant.
    ALLOWED='^(keychain-access-groups|com\.apple\.developer\.nfc\.readersession\.formats|application-identifier|com\.apple\.developer\.team-identifier|get-task-allow)$'
    REQUIRED="keychain-access-groups"
fi
note "archive is $PLATFORM"

[ -d "$APPEX" ] || fail "embedded extension missing: $APPEX"
if [ "$HAS_DISCOVERY" = "yes" ]; then
    [ -d "$APPEX_DISCOVERY" ] || fail "embedded extension missing: $APPEX_DISCOVERY"
    ALL_EXECS="$APP_EXEC $APPEX_EXEC $APPEX_DISCOVERY_EXEC"
    ALL_BUNDLES="$APP $APPEX $APPEX_DISCOVERY"
    ALL_APPEXES="$APPEX $APPEX_DISCOVERY"
    ALL_APPEX_PLISTS="$APPEX_PLIST $APPEX_DISCOVERY_PLIST"
else
    [ -d "$APPEX_DISCOVERY" ] && fail "discovery extension is iOS-only: $APPEX_DISCOVERY"
    ALL_EXECS="$APP_EXEC $APPEX_EXEC"
    ALL_BUNDLES="$APP $APPEX"
    ALL_APPEXES="$APPEX"
    ALL_APPEX_PLISTS="$APPEX_PLIST"
fi

# --- Exactly one application, exactly two plug-ins ------------------------
APP_COUNT=$(find "$ARCHIVE/Products" -maxdepth 2 -name "*.app" | wc -l | tr -d ' ')
[ "$APP_COUNT" = "1" ] || fail "expected 1 .app in archive, found $APP_COUNT"
if [ "$HAS_DISCOVERY" = "yes" ]; then
    EXPECTED_PLUGINS=2
else
    EXPECTED_PLUGINS=1
fi
PLUGIN_COUNT=$(find "$PLUGINS" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
[ "$PLUGIN_COUNT" = "$EXPECTED_PLUGINS" ] \
    || fail "expected $EXPECTED_PLUGINS plug-in(s), found $PLUGIN_COUNT"
note "one app, $EXPECTED_PLUGINS embedded extension(s)"

# --- No unexpected executable code ----------------------------------------
# The only Mach-O files permitted are the three target binaries. Helper tools,
# daemons, dylibs, frameworks, and Rust artifacts are all v1.0 exclusions.
UNEXPECTED_MACHO=$(find "$APP" -type f ! -path "$APP_EXEC" \
    ! -path "$APPEX_EXEC" \
    ! -path "$APPEX_DISCOVERY_EXEC" \
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
for BIN in $ALL_EXECS; do
    ARCHS=$(lipo -archs "$BIN" | tr ' ' '\n' | sort | tr '\n' ' ')
    [ "$ARCHS" = "$EXPECTED_ARCHS" ] \
        || fail "$BIN architectures: '$ARCHS' (expected $EXPECTED_ARCHS)"
done
note "all binaries are ${EXPECTED_ARCHS% }"

# --- Nothing diagnostic, and nothing that logs -----------------------------
# A shipped build says nothing at all: no os.Logger line, no file in the
# extension container, no line in the shared keychain trace. The sinks are
# compiled out of TestFlight and Release (see Sources/TokenExtension/TokenLog.swift
# and Sources/App/AppTrace.swift), and the trace messages are autoclosures so
# the lines are never even built.
#
# The check is for the literals rather than for the behavior, because the
# literal is the thing that survives when a gate is dropped: a new
# unguarded call reintroduces its own message text, and that text lands in
# the binary whether or not the path it sits on ever runs during a test.
FORBIDDEN_STRINGS='refineid-token-extension\.log|^(sign|session|discovery|mintFromPrime|createToken|supports|beginAuth|unseal|reader|prime): |^--(diagnostics|trace|reset-card-state|set-can|forget-can|set-pin1|prime)$'
for BIN in $ALL_EXECS; do
    LEAKED=$(strings -a "$BIN" | grep -E "$FORBIDDEN_STRINGS" | sort -u | head -10 || true)
    [ -z "$LEAKED" ] || fail "$(basename "$BIN"): diagnostic or logging strings present:
$LEAKED"
done
note "no diagnostic or logging strings in any binary"

# --- No coverage instrumentation -------------------------------------------
# Xcode 26 injects coverage into the local Swift package unless it is told
# not to on the command line, and a shipped build must carry none.
for BIN in $ALL_EXECS; do
    COVERAGE=$(otool -l "$BIN" | grep -c "__llvm_prf\|__llvm_cov" || true)
    [ "$COVERAGE" = "0" ] \
        || fail "$(basename "$BIN"): $COVERAGE coverage sections present"
done
note "no coverage instrumentation"

# --- Entitlements ----------------------------------------------------------
# Every binary must carry the platform's required entitlements; anything
# outside the allowlist fails. Signing adds Apple-managed identifier keys;
# those are expected.
entitlements_json() {
    # Answers with the binary's entitlements as JSON, or fails saying which
    # binary could not be read. An unsigned bundle otherwise reaches python3
    # with empty input and reports a JSON parse error, which says nothing
    # about the actual fault.
    local xml
    xml=$(codesign -d --entitlements - --xml "$1" 2>/dev/null || true)
    [ -n "$xml" ] || fail "$1: no entitlements; the bundle is unsigned or unreadable"
    printf '%s' "$xml" | plutil -convert json -o - - 2>/dev/null \
        || fail "$1: entitlements are not readable as a property list"
}

for BIN in $ALL_BUNDLES; do
    # Captured before it is parsed, and not piped straight into python3: a
    # `fail` inside a pipeline exits only its own subshell, so the parse
    # would still run on empty input and bury the real message.
    ENT_JSON=$(entitlements_json "$BIN")
    ENT_KEYS=$(printf '%s' "$ENT_JSON" \
        | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).keys()))')
    for KEY in $REQUIRED; do
        echo "$ENT_KEYS" | grep -qx "$KEY" || fail "$BIN: missing $KEY entitlement"
    done
    STRAY=$(echo "$ENT_KEYS" | grep -vE "$ALLOWED" || true)
    [ -z "$STRAY" ] || fail "$BIN: unreviewed entitlements:
$STRAY"
done
# The network grant belongs to the app and to nothing else. An extension
# that could open a connection would be a second, unreviewable path off
# this machine, and neither of ours has any reason to reach one.
if [ "$PLATFORM" = "macOS" ]; then
    for BIN in $APPEX_EXEC; do
        entitlements_json "$BIN" \
            | plutil -convert json -o - -- - 2>/dev/null \
            | grep -q "network.client" \
            && fail "$BIN: extensions must not carry a network entitlement"
    done
    note "the network entitlement is the app's alone"
fi

note "entitlements match the reviewed allowlist"

# --- The app's own keychain group comes first ------------------------------
# iOS only, and it is not cosmetic. An item added without an explicit
# kSecAttrAccessGroup lands in the FIRST group of the writer's entitlement,
# so putting com.apple.token ahead of the app's own group silently moves
# every prime and stored credential out of reach of both extensions - and
# the failure looks like a card that was never primed.
if [ "$PLATFORM" = "iOS" ]; then
    APP_ENT_JSON=$(entitlements_json "$APP")
    FIRST_GROUP=$(printf '%s' "$APP_ENT_JSON" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["keychain-access-groups"][0])')
    case "$FIRST_GROUP" in
        *.fi.refineid.ReFineID) ;;
        *) fail "first keychain access group is '$FIRST_GROUP', not the app's own" ;;
    esac
    note "app's own keychain group is first ($FIRST_GROUP)"
fi

# --- Same team signs app and extensions -----------------------------------
TEAM_APP=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ -n "$TEAM_APP" ] || fail "could not read the app's team identifier"
for BIN in $ALL_APPEXES; do
    TEAM_EXT=$(codesign -dv "$BIN" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [ "$TEAM_APP" = "$TEAM_EXT" ] \
        || fail "team mismatch: app '$TEAM_APP' vs $BIN '$TEAM_EXT'"
done
note "app and both extensions signed by the same team ($TEAM_APP)"

# --- Versions agree --------------------------------------------------------
V_APP=$(plutil -extract CFBundleShortVersionString raw "$APP_PLIST")
B_APP=$(plutil -extract CFBundleVersion raw "$APP_PLIST")
for PLIST in $ALL_APPEX_PLISTS; do
    V_EXT=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
    B_EXT=$(plutil -extract CFBundleVersion raw "$PLIST")
    [ "$V_APP" = "$V_EXT" ] || fail "version mismatch: app $V_APP vs $PLIST $V_EXT"
    [ "$B_APP" = "$B_EXT" ] || fail "build mismatch: app $B_APP vs $PLIST $B_EXT"
done
note "app and both extensions are version $V_APP ($B_APP)"

# --- Export compliance is answered in the bundle ---------------------------
# Absent, App Store Connect asks at every upload and the answer is recorded
# per build rather than in reviewed source. The value itself is a release
# decision; that it is stated at all is an archive property.
if [ "$PLATFORM" = "iOS" ]; then
    plutil -extract ITSAppUsesNonExemptEncryption raw "$APP_PLIST" >/dev/null 2>&1 \
        || fail "ITSAppUsesNonExemptEncryption missing from the app Info.plist"
    COMPLIANCE=$(plutil -extract ITSAppUsesNonExemptEncryption raw "$APP_PLIST")
    # Declaring non-exempt is a claim that Apple holds export
    # compliance documentation for the app and issued a code against
    # it. Both halves were verified against App Store Connect on
    # 2026-08-07: an upload declaring true without a code is rejected
    # mid-transfer with 90592, and Apple refuses to accept
    # documentation at all for standard published algorithms outside
    # the French store. Until the ANSSI attestation the honest pair is
    # therefore false with no code -- exempt from documentation
    # requirements, which is what the key means by exempt. See
    # Documentation/export-compliance.md.
    if [ "$COMPLIANCE" = "true" ]; then
        CODE=$(plutil -extract ITSEncryptionExportComplianceCode raw "$APP_PLIST" 2>/dev/null || true)
        [ -n "$CODE" ] || fail "ITSAppUsesNonExemptEncryption is true but
  ITSEncryptionExportComplianceCode is missing. App Store Connect
  rejects that upload with 90592. Either add the code Apple issued
  against filed documentation, or declare false until one exists."
        note "export compliance answered (non-exempt, code present)"
    else
        note "export compliance answered (exempt from documentation)"
    fi
fi

# --- The AID lives on the discovery extension only -------------------------
# ctkd polls with the AID an extension declares, but a driver that declares
# one stops being invoked for the app's own slot. Splitting the roles is what
# makes system-Safari login work; an archive that merges them is broken.
declares_aid() {
    plutil -convert json -o - "$1" | python3 -c '
import json, sys
attrs = json.load(sys.stdin).get("NSExtension", {}).get("NSExtensionAttributes", {})
sys.exit(0 if "com.apple.ctk.aid" in attrs else 1)'
}
# Only iOS polls for a contactless card, and only iOS embeds the
# extension that declares what to poll for.
if [ "$HAS_DISCOVERY" = "yes" ]; then
    declares_aid "$APPEX_DISCOVERY_PLIST" \
        || fail "discovery extension declares no com.apple.ctk.aid; no card is ever polled"
fi
! declares_aid "$APPEX_PLIST" \
    || fail "token extension declares com.apple.ctk.aid; the token will never be minted"
if [ "$HAS_DISCOVERY" = "yes" ]; then
    note "AID declared by the discovery extension only"
else
    note "no AID declared; a Mac reader hands the card over without one"
fi

# --- Privacy manifest present ----------------------------------------------
[ -f "$APP_RESOURCES/PrivacyInfo.xcprivacy" ] \
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

echo "PASS: $ARCHIVE ($PLATFORM)"
