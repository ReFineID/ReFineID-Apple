#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

set -euo pipefail

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
  5A803C24-0C62-4249-934A-50EB31519887 \
  build/Build/Products/Debug-iphonesimulator/ReFineID.app

echo "Done."
