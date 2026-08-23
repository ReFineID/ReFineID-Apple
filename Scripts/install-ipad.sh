#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

set -euo pipefail

UUID=$(xcrun simctl list devices available -j | jq -r '.devices[][] | select((.name | startswith("iPad")) and .state == "Booted") | .udid')

cd "$(dirname "$0")/.."

echo "Building for iPad simulator..."
xcodebuild \
  -project ReFineID.xcodeproj \
  -scheme ReFineID \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath build \
  build \
  | tail -3

echo "Installing to iPad simulator..."
xcrun simctl install \
  $UUID \
  build/Build/Products/Debug-iphonesimulator/ReFineID.app

echo "Done."
