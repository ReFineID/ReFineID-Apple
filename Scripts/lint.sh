#!/usr/bin/env bash
#
# Lint gate: 
# - swift-format owns layout
# - SwiftLint owns defects
# -typing-discipline custom rules
#
# Both must be silent (strict) for the gate to pass.
# 
# Run from anywhere; operates on the repository.

set -euo pipefail
cd "$(dirname "$0")/.."

echo "swift format lint..."
swift format lint --strict --recursive Sources Tests CardCore/Sources CardCore/Package.swift

echo "swiftlint..."
swiftlint lint --quiet

echo "lint gate PASS"
