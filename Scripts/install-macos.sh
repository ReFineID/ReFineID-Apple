#!/usr/bin/env bash
#
# Build, verify and install ReFineID into /Applications on this Mac.
#
# /Applications is the only place a copy may live. A CryptoTokenKit
# driver is registered by the system from wherever it finds the bundle,
# so every stray copy -- a DerivedData build, a /tmp build, a second one
# in ~/Applications -- becomes a competing registration for the same
# driver class. The system then picks one, silently, and it is not
# necessarily the one being edited. This script installs to
# /Applications and removes the rest.
#
# The signature is checked before installing, and a revoked certificate
# fails the run. That is not a formality: a revoked certificate does not
# merely warn, it stops launchd from spawning the token extension at all
# (POSIX 163, "Launchd job spawn failed"). ctkd then reports "no token
# driver found" for a perfectly good card, Safari is offered no
# identity, and the site never asks for a certificate -- which looks
# exactly like a bug in this app and is not one.
#
# Usage:
#
#   Scripts/install-macos.sh                 build, verify, install
#   Scripts/install-macos.sh --check         verify what is installed
#   Scripts/install-macos.sh --configuration Release
#
set -euo pipefail
cd "$(dirname "$0")/.."

app_name="ReFineID.app"
installed="/Applications/${app_name}"
derived_data="/tmp/refineid-macos-install"
configuration="Debug"
check_only="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check_only="yes"; shift ;;
    --configuration) configuration="${2:?--configuration needs a value}"; shift 2 ;;
    *) echo "usage: $0 [--check] [--configuration NAME]" >&2; exit 2 ;;
  esac
done

# Every install carries the ten-minute bucket it was built in, so the
# About window answers "am I running the copy just installed?" - a
# build number that only moved on release cuts could not.
if [[ "$check_only" == "no" ]]; then
  Scripts/stamp-version.sh
fi

fail() { echo "install-macos: $*" >&2; exit 1; }
note() { echo "install-macos: $*"; }

# Every signing identity this Mac could use, and whether it is usable.
# `security` reports a revoked certificate as a valid identity with a
# parenthesised error, so the error is what has to be read.
report_identities() {
  note "code-signing identities:"
  security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /'
}

# Refuses anything the system will not launch: a broken seal, or a
# certificate that has been revoked since the bundle was signed.
verify_signature() {
  local bundle="$1"
  local output
  if ! output="$(codesign --verify --deep --strict "$bundle" 2>&1)"; then
    echo "$output" | sed 's/^/  /' >&2
    if echo "$output" | grep -q "CSSMERR_TP_CERT_REVOKED"; then
      report_identities >&2
      fail "the signing certificate is REVOKED. launchd will refuse to spawn the
  token extension, ctkd will report no token driver for the card, and
  Safari will never be offered an identity. Issue a new development
  certificate in Xcode (Settings > Accounts > Manage Certificates) and
  run this again."
    fi
    fail "signature verification failed for ${bundle}"
  fi
  note "signature valid: $(codesign -dvv "$bundle" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
}

# Any macOS copy outside /Applications is a competing driver
# registration. iOS build products are left alone: they carry no
# `Contents/MacOS`, cannot be loaded here, and deleting them would throw
# away device builds for no benefit.
is_macos_bundle() {
  [[ -d "$1/Contents/MacOS" ]]
}

remove_stray_copies() {
  local found=0
  local candidates
  candidates="$(
    {
      mdfind -name "$app_name" 2>/dev/null | grep -F "/${app_name}" || true
      # Deep enough to reach a build nested inside a scratch directory:
      # /private/tmp/<agent>/<session>/scratchpad/<build>/Build/Products/
      # <configuration>/ReFineID.app is already nine levels down.
      for root in /tmp /private/tmp "$HOME/Library/Developer/Xcode/DerivedData"; do
        find "$root" -maxdepth 12 -name "$app_name" -type d 2>/dev/null || true
      done
    } | sort -u
  )"
  while IFS= read -r stray; do
    [[ -z "$stray" ]] && continue
    [[ "$stray" == "$installed" ]] && continue
    is_macos_bundle "$stray" || continue
    note "removing stray macOS copy: $stray"
    rm -rf "$stray"
    found=$((found + 1))
  done <<<"$candidates"
  [[ "$found" -eq 0 ]] && note "no stray macOS copies found"
  return 0
}

# What the system currently believes about our driver.
report_registrations() {
  note "registered CryptoTokenKit drivers for this app:"
  pluginkit -m -p com.apple.ctk-tokens -vvv 2>/dev/null \
    | grep -A2 "fi.refineid" | sed 's/^/  /' || note "  (none registered)"
  note "what the smart-card system sees:"
  system_profiler SPSmartCardsDataType 2>/dev/null \
    | sed -n '/SmartCard Drivers/,/Available SmartCards (keychain)/p' \
    | grep -i refineid | sed 's/^/  /' || note "  (no ReFineID driver listed)"
}

if [[ "$check_only" == "yes" ]]; then
  [[ -d "$installed" ]] || fail "nothing installed at ${installed}"
  verify_signature "$installed"
  report_registrations
  exit 0
fi

note "building ${configuration} for macOS"
xcodebuild \
  -project ReFineID.xcodeproj \
  -scheme ReFineID \
  -configuration "$configuration" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates \
  -quiet \
  build

built="${derived_data}/Build/Products/${configuration}/${app_name}"
[[ -d "$built" ]] || fail "build produced no ${app_name}"

# Verified BEFORE anything is replaced, so a bad certificate leaves the
# working copy in place rather than a broken one.
verify_signature "$built"

pkill -x ReFineID 2>/dev/null || true
sleep 1

note "installing to ${installed}"
rm -rf "$installed"
cp -R "$built" "$installed"
verify_signature "$installed"

remove_stray_copies
rm -rf "$derived_data"

# The system registers the extension when the containing app is seen,
# and the app is quit again afterwards so a fresh install leaves nothing
# running that the holder did not open themselves.
#
# The window no longer reads the card at all, so it can no longer hold
# it while the extension signs -- that fault is fixed at the source. The
# quit stays because Diagnostics and the Card manager still do card I/O
# on request, and an installer should not leave either of them up.
note "registering the extension"
open -a "$installed"
sleep 3
osascript -e 'tell application "ReFineID" to quit' 2>/dev/null || true
sleep 1
pkill -x ReFineID 2>/dev/null || true
note "app quit so it does not hold the card"

report_registrations

# A replaced driver does not take over a token ctkd already minted: the
# daemon caches the published identity and re-asks a driver only on a
# card insertion event. A PC/SC reset, an exclusive unpower disconnect,
# and the extension process dying were each tried and none re-minted
# (measured 2026-08-05); restarting ctkd is the one software action that
# does. Skipping this leaves Safari offering identities whose driver
# build no longer exists, and the next login hangs on a signature no
# process will ever answer.
if system_profiler SPSmartCardsDataType 2>/dev/null | grep -q "ATR:"; then
  if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
    note "a card is inserted; restarting the CryptoTokenKit stack so the new driver serves it"
    # The whole family, not only ctkd: ctkpcscd owns the readers, ctkahp
    # hosts the PIN sheet, ctkbind the pairing agent. All respawn on
    # demand from launchd. ctkpcscd shrugs off a plain TERM - observed
    # 2026-08-05 keeping its PID through killall - so it gets KILL.
    sudo killall -9 com.apple.ctkpcscd 2>/dev/null || true
    sudo killall ctkahp ctkbind 2>/dev/null || true
    if sudo killall ctkd 2>/dev/null; then
      for _ in 1 2 3 4 5; do
        sleep 2
        sc_auth identities 2>/dev/null | grep -q "fi.refineid" && break
      done
      if sc_auth identities 2>/dev/null | grep -q "fi.refineid"; then
        note "token re-minted by the new driver:"
        sc_auth identities 2>/dev/null | sed 's/^/  /'
      else
        # Cutting ctkd out from under an open reader session can wedge
        # the reader's firmware until it re-enumerates: the ACR39U was
        # seen dropping off the USB bus entirely (2026-08-05), where no
        # daemon restart can reach it.
        note "no token re-appeared. Unplug and replug the reader, card inserted."
      fi
      note "done."
      exit 0
    fi
    note "ctkd restart failed"
  fi
  note "done. Remove and re-insert the card so ctkd asks the new driver for a token."
else
  note "done. No card inserted; the next insertion uses the new driver."
fi
