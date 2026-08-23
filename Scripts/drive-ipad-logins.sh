#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

# Drives iPad Safari card authentication logins to card.refineid.fi, suomi.fi, and posti.fi/omaposti.
#
# Usage:
#   Scripts/drive-ipad-logins.sh [--site <card|suomi|omaposti|all>] [--direct] [--udid <simulator-udid>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SITE="all"
DIRECT=0
IPAD_UDID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site)
      SITE="$2"
      shift 2
      ;;
    --direct)
      DIRECT=1
      shift
      ;;
    --udid)
      IPAD_UDID="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: Scripts/drive-ipad-logins.sh [--site <card|suomi|omaposti|all>] [--direct] [--udid <simulator-udid>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$IPAD_UDID" ]]; then
  IPAD_UDID="$(python3 - << 'PYEOF'
import subprocess, json
out = subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'])
data = json.loads(out)
found = None
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' not in runtime:
        continue
    for dev in devices:
        if 'iPad' in dev.get('name', ''):
            found = dev.get('udid')
            break
    if found:
        break
print(found or '')
PYEOF
)"
fi

if [[ -z "$IPAD_UDID" ]]; then
  echo "Error: No available iPad simulator found." >&2
  exit 1
fi

echo "==> Using iPad simulator: $IPAD_UDID"
xcrun simctl boot "$IPAD_UDID" 2>/dev/null || true

run_direct_login() {
  local target_url="$1"
  local site_name="$2"
  echo "==> Direct opening Safari on iPad simulator to: $target_url ($site_name)"
  xcrun simctl openurl "$IPAD_UDID" "$target_url"
  sleep 3
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local screenshot_path="/tmp/ipad_login_${site_name}_${timestamp}.png"
  xcrun simctl io "$IPAD_UDID" screenshot "$screenshot_path"
  echo "==> Captured screenshot: $screenshot_path"
}

run_uitest_login() {
  local test_method="$1"
  local site_name="$2"
  echo "==> Running XCUITest driver for $site_name ($test_method)..."
  TEST_RUNNER_REFINEID_REAL_CARD_TESTS=1 \
  TEST_RUNNER_REFINEID_SAFARI_OPEN_VIA_APP=1 \
  xcodebuild test \
    -project "$REPO_ROOT/ReFineID.xcodeproj" \
    -scheme "ReFineID" \
    -destination "id=$IPAD_UDID" \
    -only-testing:"ReFineIDUITests/SafariCardLoginUITests/$test_method" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY=""
}

drive_site() {
  local target="$1"
  case "$target" in
    card)
      if [[ "$DIRECT" -eq 1 ]]; then
        run_direct_login "https://card.refineid.fi" "card_refineid"
      else
        run_uitest_login "testLoginCardRefineID" "card.refineid.fi"
      fi
      ;;
    suomi)
      if [[ "$DIRECT" -eq 1 ]]; then
        run_direct_login "https://www.suomi.fi" "suomi_fi"
      else
        run_uitest_login "testLoginSuomiFi" "suomi.fi"
      fi
      ;;
    omaposti)
      if [[ "$DIRECT" -eq 1 ]]; then
        run_direct_login "https://www.posti.fi/omaposti" "omaposti"
      else
        run_uitest_login "testLoginOmaPosti" "posti.fi/omaposti"
      fi
      ;;
    all)
      drive_site card
      drive_site suomi
      drive_site omaposti
      ;;
    *)
      echo "Unknown site: $target" >&2
      exit 1
      ;;
  esac
}

drive_site "$SITE"
echo "==> Login driver runs completed."
