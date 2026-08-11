#!/usr/bin/env bash
#
# Copyright 2026 Petri Koistinen
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#        https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
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
swift format lint --strict --recursive \
  Sources Tests CardCore/Sources CardCore/Package.swift \
  PKCS11Bridge/Sources PKCS11Bridge/Tests PKCS11Bridge/Package.swift \
  Scripts/BrainpoolBenchmark.swift

echo "swiftlint..."
swiftlint lint --quiet

echo "lint gate PASS"
