#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

set -euo pipefail

cd "$(dirname "$0")/.."

Scripts/install-iphone.sh
Scripts/install-ipad.sh
