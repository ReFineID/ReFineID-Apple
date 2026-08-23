#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Usage: Scripts/lint.sh
#
# The lint gate, and the only SwiftLint invocation the pre-commit hook
# runs. Run this script. Do not run:
#
#   swiftlint lint --autocorrect --format --progress --check-for-updates --enable-all-rules
#
# --enable-all-rules ignores disabled_rules, so it cannot honour the
# carve register in .swiftlint.yml (it turns on rules that contradict
# each other and rules that fight swift-format). --format reformats
# with SourceKit, a different layout owner than swift-format.
#
# Gate:
# - swift-format owns layout
# - SwiftLint owns defects (strict, carve register, baseline)
# - typing-discipline custom rules live in .swiftlint.yml
#
# Both tools must be silent for the gate to pass. Run from anywhere;
# operates on the repository.

set -euo pipefail
cd "$(dirname "$0")/.."

format_paths=(
  Sources Tests
  CardCore/Sources/CardCore CardCore/Sources/RappEngine
  CardCore/Tests CardCore/Package.swift
  PKCS11Bridge/Sources PKCS11Bridge/Tests PKCS11Bridge/Package.swift
  Scripts/BrainpoolBenchmark.swift
)

echo "swift format lint..."
swift format lint --strict --recursive "${format_paths[@]}"

echo "swiftlint..."
# The baseline records the structural debt (type ordering, file splits,
# magic numbers) present when the gate was raised. New findings fail;
# paying debt down shrinks the baseline via --write-baseline.
swiftlint lint --quiet --baseline .swiftlint-baseline.json

echo "lint gate PASS"
