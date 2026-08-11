#!/usr/bin/env bash
#
# Copyright 2026 Petri Koistinen
# Licensed under the Apache License, Version 2.0.
#
# Build, sign, install, and launch an optimized diagnostic build on one iPhone.
#
# The calendar version and ten-minute build number are command-line Xcode
# overrides. The project file is never edited, so repeated device builds do
# not create version-only Git changes.
#
# Usage:
#
#   Scripts/install-ios-development.sh <device name or identifier>
#
# Example:
#
#   Scripts/install-ios-development.sh My-iPhone

set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-}"
if [[ -z "$device" ]]; then
  echo "usage: $0 <device name or identifier>" >&2
  exit 2
fi

read -r yy mm dd hh mn <<<"$(date -u '+%y %m %d %H %M')"
version="${yy}.$((10#$mm)).$((10#$dd))"
build=$((10#$hh * 10 + 10#$mn / 10))
derived_data="/tmp/refineid-apple-development"
configuration="Profile"
app_path="${derived_data}/Build/Products/${configuration}-iphoneos/ReFineID.app"

echo "building ReFineID ${version} (${build}) (${configuration}, optimized) for ${device}"
xcodebuild \
  -project ReFineID.xcodeproj \
  -scheme ReFineID \
  -configuration "$configuration" \
  -destination "platform=iOS,id=${device}" \
  -derivedDataPath "$derived_data" \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build" \
  CLANG_COVERAGE_MAPPING=NO \
  ENABLE_CODE_COVERAGE=NO \
  -quiet \
  build

codesign --verify --deep --strict "$app_path"
xcrun devicectl device install app --device "$device" "$app_path"
xcrun devicectl device process launch \
  --device "$device" \
  --terminate-existing \
  fi.refineid.ReFineID

echo "installed and launched ReFineID ${version} (${build})"
