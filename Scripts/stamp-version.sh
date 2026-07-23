#!/usr/bin/env bash
#
# Stamp the calendar release version onto the Xcode project.
#
# Run this MANUALLY when cutting a release.
#
# Sets, across every target's build settings:
#
#   MARKETING_VERSION (CFBundleShortVersionString) = YY.M.D
#       Release date, no zero padding.
#
#   CURRENT_PROJECT_VERSION (CFBundleVersion)      = H * 10 + M / 10
#       The ten-minute bucket the build is cut in.
#
# Usage:
#
#   Scripts/stamp-version.sh            # stamp the project
#   Scripts/stamp-version.sh --dry-run  # print the version, change nothing

set -euo pipefail
cd "$(dirname "$0")/.."

read -r yy mm dd hh mn <<<"$(date '+%y %m %d %H %M')"
version="${yy}.$((10#$mm)).$((10#$dd))"
bucket=$((10#$hh * 10 + 10#$mn / 10))

if [[ "${1:-}" == "--dry-run" ]]; then
  echo "would stamp ${version} (${bucket})"
  exit 0
fi

pbxproj="ReFineID.xcodeproj/project.pbxproj"
sed -i '' -E "s/(MARKETING_VERSION = )[^;]+;/\1${version};/g" "$pbxproj"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[^;]+;/\1${bucket};/g" "$pbxproj"

echo "stamped ${version} (${bucket}). Next: review the diff, commit, tag ios-v${version}-<channel>.${bucket}"
