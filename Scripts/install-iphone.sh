#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building for iPhone..."
xcodebuild \
  -project ReFineID.xcodeproj \
  -scheme ReFineID \
  -configuration Debug \
  -destination 'id=8830EBA0-0A26-5B3E-BE48-A974338DC57B' \
  -derivedDataPath build/DerivedData \
  build \
  | tail -5

echo "Installing to iPhone..."
xcrun devicectl device install app \
  --device 8830EBA0-0A26-5B3E-BE48-A974338DC57B \
  build/DerivedData/Build/Products/Debug-iphoneos/ReFineID.app \
  2>&1 | grep -E "App installed|bundleID"

echo "Done."
