#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

set -euo pipefail

UUID=$(xcrun devicectl list devices | grep -Eo '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')

cd "$(dirname "$0")/.."

echo "Building for iPhone..."
xcodebuild \
  -project ReFineID.xcodeproj \
  -scheme ReFineID \
  -configuration Debug \
  -destination "id=$UUID" \
  -derivedDataPath build/DerivedData \
  build \
  | tail -5

echo "Installing to iPhone..."
xcrun devicectl device install app \
  --device $UUID \
  build/DerivedData/Build/Products/Debug-iphoneos/ReFineID.app \
  2>&1 | grep -E "App installed|bundleID"

echo "Done."
