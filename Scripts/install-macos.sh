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

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks"
lsregister="${lsregister}/LaunchServices.framework/Support/lsregister"

# Deleting a bundle does not withdraw what Launch Services recorded
# about it, and an iOS bundle that is rightly left on disk still claims
# our identifier. Launch Services answers identifier lookups with one
# winner among the claimants, so a stray decides what the Dock and the
# switcher draw for the running app, and a build product that carries no
# macOS icon draws nothing at all. Withdrawing the claim costs a device
# build nothing: rebuilding it registers the bundle again.
unregister_copy() {
  [[ -x "$lsregister" ]] || return 0
  "$lsregister" -u "$1" 2>/dev/null || true
}

# Build products are not documents. Left indexed, every configuration of
# every checkout answers a search for the app by name, and the one copy
# that may be launched is buried among them.
# The marker is placed before the build runs, because a tree is indexed
# as it is written and a marker added afterwards only stops the next
# pass.
hide_from_spotlight() {
  mkdir -p "$1" 2>/dev/null || return 0
  touch "$1/.metadata_never_index" 2>/dev/null || true
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
      # The build/ directory in this checkout holds the archives a
      # release is cut from, which mdfind stops reporting once the tree
      # is hidden from the index.
      for root in /tmp /private/tmp "$HOME/Library/Developer/Xcode/DerivedData" build; do
        find "$root" -maxdepth 12 -name "$app_name" -type d 2>/dev/null || true
      done
    } | sort -u
  )"
  while IFS= read -r stray; do
    [[ -z "$stray" ]] && continue
    [[ "$stray" == "$installed" ]] && continue
    unregister_copy "$stray"
    if ! is_macos_bundle "$stray"; then
      note "unregistered non-macOS copy: $stray"
      continue
    fi
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

# A card insertion is CryptoTokenKit's supported discovery boundary.
# Replacing a live extension leaves ctkd holding the old token and
# executable; restarting ctkd only strands the reader daemons on dead
# XPC endpoints. Leave the reader connected and remove only the card.
card_is_inserted() {
  system_profiler SPSmartCardsDataType 2>/dev/null | grep -q "ATR:"
}

refineid_identity_is_live() {
  sc_auth identities 2>/dev/null | grep -q "fi.refineid"
}

wait_for_card_release() {
  card_is_inserted || return 0
  if [[ ! -t 0 ]]; then
    fail "a card is inserted. Remove only the card, leave the USB reader connected, and run this again."
  fi
  note "remove the card; leave the USB reader connected"
  while card_is_inserted; do
    sleep 1
  done
  note "card removed; waiting for CryptoTokenKit to withdraw its token"
  for _ in 1 2 3 4 5; do
    refineid_identity_is_live || return 0
    sleep 1
  done
  fail "CryptoTokenKit still publishes the removed card. Log out before replacing the extension."
}

# PlugInKit may retain an idle extension process briefly after its card
# leaves. Ending our processes is sufficient; the next insertion starts
# the copy inside the newly installed app.
stop_refineid_extensions() {
  pkill -f "/ReFineIDTokenExtension.appex/Contents/MacOS/ReFineIDTokenExtension" \
    2>/dev/null || true
  pkill -f "/ReFineIDDiscoveryExtension.appex/Contents/MacOS/ReFineIDDiscoveryExtension" \
    2>/dev/null || true
}

if [[ "$check_only" == "yes" ]]; then
  [[ -d "$installed" ]] || fail "nothing installed at ${installed}"
  verify_signature "$installed"
  report_registrations
  exit 0
fi

hide_from_spotlight "$derived_data"
hide_from_spotlight "$HOME/Library/Developer/Xcode/DerivedData"
hide_from_spotlight build

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
wait_for_card_release
stop_refineid_extensions

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
note "done. Insert the card; CryptoTokenKit will mint it with the new driver."
