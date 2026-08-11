#!/usr/bin/env bash
#
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Archive, verify and upload ReFineID to TestFlight, for iOS and macOS.
#
# Every build that reaches another person goes through here, and the
# order matters: nothing is uploaded that has not first passed
# `inspect-archive.sh`. That script is the promise in executable form --
# no diagnostics, no logging, no unreviewed entitlement, no coverage
# instrumentation, both binaries on one team -- and a release path that
# could skip it would eventually skip it.
#
# The configuration is TestFlight, which defines no DEBUG and excludes
# the diagnostics sources from the target. See
# `Documentation/decisions.md`, "Diagnostics is a development tool".
#
# Version and build come from the clock, not from the project file:
# marketing version is the calendar date and build is the ten-minute
# bucket of UTC it was cut in, so two builds on one day always increase
# regardless of the build machine's zone or daylight saving and the project is never dirtied by a release.
#
# Usage:
#
#   Scripts/release-testflight.sh                 both platforms, upload
#   Scripts/release-testflight.sh --platform ios
#   Scripts/release-testflight.sh --platform macos
#   Scripts/release-testflight.sh --no-upload     archive and verify only
#
# Credentials, for uploading (App Store Connect > Integrations > Keys):
#
#   ASC_KEY_ID      the key's ID
#   ASC_ISSUER_ID   the issuer UUID shown above the key list
#   the .p8 itself in ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
#
set -euo pipefail
cd "$(dirname "$0")/.."

# The App Store Connect key id and issuer id, if they have been left in
# the standard place beside the .p8 rather than exported by hand. The
# file is the machine owner's, outside the repository; it is sourced
# only when present, so a machine without it just needs the two
# variables in the environment as before.
[ -f "$HOME/.appstoreconnect/env" ] && . "$HOME/.appstoreconnect/env"

platforms="ios macos"
upload="yes"
out="build/testflight"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) platforms="${2:?--platform needs ios or macos}"; shift 2 ;;
    --no-upload) upload="no"; shift ;;
    *) echo "usage: $0 [--platform ios|macos] [--no-upload]" >&2; exit 2 ;;
  esac
done

fail() { echo "release: $*" >&2; exit 1; }
note() { echo "release: $*"; }

# A release describes a commit. An archive cut from a dirty tree
# describes nothing anybody can go back to.
[ -z "$(git status --porcelain)" ] || fail "working tree is dirty; commit or stash first."

read -r yy mm dd hh mn <<<"$(date -u '+%y %m %d %H %M')"
version="${yy}.$((10#$mm)).$((10#$dd))"
build=$((10#$hh * 10 + 10#$mn / 10))
commit="$(git rev-parse --short HEAD)"
note "cutting ${version} (${build}) from ${commit}"

key_path=""
if [ "$upload" = "yes" ]; then
  : "${ASC_KEY_ID:?set ASC_KEY_ID, or pass --no-upload}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID, or pass --no-upload}"
  key_path="${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  [ -f "$key_path" ] || fail "no key at ${key_path}
  Create one in App Store Connect > Integrations > Keys, download the
  .p8 once (Apple does not offer it twice), and put it there."
fi

mkdir -p "$out"

# One platform: archive, verify, then export -- and only then upload.
release_one() {
  local platform="$1" destination archive exported

  case "$platform" in
    ios) destination='generic/platform=iOS' ;;
    macos) destination='generic/platform=macOS' ;;
    *) fail "unknown platform: ${platform}" ;;
  esac

  archive="${out}/ReFineID-${platform}.xcarchive"
  exported="${out}/${platform}"
  rm -rf "$archive" "$exported"

  note "[${platform}] archiving"
  xcodebuild archive \
    -project ReFineID.xcodeproj \
    -scheme ReFineID \
    -configuration TestFlight \
    -destination "$destination" \
    -archivePath "$archive" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build" \
    CLANG_COVERAGE_MAPPING=NO \
    ENABLE_CODE_COVERAGE=NO \
    -allowProvisioningUpdates \
    -quiet

  # The gate. Nothing below this line runs on an archive that failed it.
  note "[${platform}] inspecting"
  Scripts/inspect-archive.sh "$archive"

  note "[${platform}] exporting"
  local options="${out}/ExportOptions-${platform}.plist"
  cp Config/ExportOptions-AppStore.plist "$options"
  if [ "$upload" = "yes" ]; then
    plutil -replace destination -string upload "$options"
  fi

  # macOS ships bash 3.2, where "${array[@]}" on an empty array trips
  # `set -u`. The two calls are spelled out rather than guarded with the
  # ${arr[@]+...} incantation, which is shorter and reads like a typo.
  # -allowProvisioningUpdates on the export too, not only the archive:
  # the archive is signed for development and the export re-signs it for
  # distribution, which needs App Store profiles that do not exist until
  # something is allowed to create them.
  if [ "$upload" = "yes" ]; then
    xcodebuild -exportArchive \
      -archivePath "$archive" \
      -exportOptionsPlist "$options" \
      -exportPath "$exported" \
      -allowProvisioningUpdates \
      -authenticationKeyPath "$key_path" \
      -authenticationKeyID "$ASC_KEY_ID" \
      -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  else
    xcodebuild -exportArchive \
      -archivePath "$archive" \
      -exportOptionsPlist "$options" \
      -exportPath "$exported" \
      -allowProvisioningUpdates
  fi

  if [ "$upload" = "yes" ]; then
    note "[${platform}] uploaded ${version} (${build})"
  else
    note "[${platform}] exported to ${exported}"
  fi
}

for platform in $platforms; do
  release_one "$platform"
done

note "done: ${version} (${build}) from ${commit}"
if [ "$upload" = "yes" ]; then
  note "App Store Connect takes a few minutes to finish processing a build"
  note "before it can be assigned to a TestFlight group."
fi
