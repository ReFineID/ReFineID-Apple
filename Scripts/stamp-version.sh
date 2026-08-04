#!/usr/bin/env bash
#
# Stamp the calendar release version onto the Xcode project.
#
# Run manually when cutting a release; install-macos.sh also runs it,
# so every installed build carries the bucket it was built in.
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
#   Scripts/stamp-version.sh --tag dev  # stamp, then tag the CURRENT commit
#
# Tagging is opt-in on purpose. Stamping only sets a build number, which
# is wanted often; a tag asserts that a particular commit is a release
# for a named channel, which is a decision and is wanted rarely. The
# channel is one of dev, beta or rc.

set -euo pipefail
cd "$(dirname "$0")/.."

read -r yy mm dd hh mn <<<"$(date '+%y %m %d %H %M')"
version="${yy}.$((10#$mm)).$((10#$dd))"
bucket=$((10#$hh * 10 + 10#$mn / 10))

channel=""
case "${1:-}" in
  --dry-run)
    echo "would stamp ${version} (${bucket})"
    exit 0
    ;;
  --tag)
    channel="${2:-}"
    case "$channel" in
      dev | beta | rc) ;;
      *)
        echo "--tag needs a channel: dev, beta or rc" >&2
        exit 2
        ;;
    esac
    ;;
  "") ;;
  *)
    echo "unknown argument: ${1}" >&2
    exit 2
    ;;
esac

pbxproj="ReFineID.xcodeproj/project.pbxproj"
sed -i '' -E "s/(MARKETING_VERSION = )[^;]+;/\1${version};/g" "$pbxproj"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[^;]+;/\1${bucket};/g" "$pbxproj"

if [[ -n "$channel" ]]; then
  tag="ios-v${version}-${channel}.${bucket}"
  # The stamp itself is left uncommitted deliberately: the tag names the
  # commit that is already reviewed, and quietly committing a project
  # file on the way to tagging would hide a change nobody read.
  if ! git diff --quiet -- "$pbxproj"; then
    echo "stamped ${version} (${bucket}), NOT tagged: commit the stamp first, then re-run" >&2
    exit 1
  fi
  git tag -a "$tag" -m "ReFineID ${version} (${bucket}), ${channel}"
  echo "stamped ${version} (${bucket}) and tagged ${tag}. Push it with: git push origin ${tag}"
  exit 0
fi

echo "stamped ${version} (${bucket}). Next: review the diff, commit, then Scripts/stamp-version.sh --tag <channel>"
