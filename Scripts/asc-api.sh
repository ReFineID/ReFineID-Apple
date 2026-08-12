#!/usr/bin/env bash
#
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#

# Call the App Store Connect API with a freshly minted token.
#
# TestFlight housekeeping -- who is a tester, which build a group is on,
# resending an invite that expired -- is a handful of REST calls, and
# doing them through the web UI leaves no record of what was done. This
# is the smallest thing that makes them repeatable: a token from
# Scripts/asc-jwt.rb, curl, and the path you care about.
#
# It deliberately knows nothing about the app. Identifiers are secrets'
# neighbours -- the .p8 is the real secret, but the key and issuer IDs
# name it -- so none of them are written down here; they come from the
# environment and from arguments. See the memory notes, not the repo,
# for this app's values.
#
# Usage:
#
#   Scripts/asc-api.sh <path>                  GET
#   Scripts/asc-api.sh -X POST <path> <json>   body as an argument
#   Scripts/asc-api.sh -X POST <path> -        body from stdin
#
# <path> may be a full URL or a path like /v1/apps. Output is the raw
# JSON body; a non-2xx response prints the body and exits non-zero.
#
# Recipes, with $app the App Store Connect app ID:
#
#   # the external group, and the builds testers can actually install
#   Scripts/asc-api.sh "/v1/apps/${app}/betaGroups"
#   Scripts/asc-api.sh "/v1/betaGroups/${group}/builds"
#
#   # find a tester; state is INVITED until they redeem it
#   Scripts/asc-api.sh "/v1/betaTesters?filter[email]=${email}&include=betaGroups"
#
#   # resend an expired invite to a tester who is already in a group
#   Scripts/asc-api.sh -X POST /v1/betaTesterInvitations - <<JSON
#   {"data":{"type":"betaTesterInvitations","relationships":{
#     "app":{"data":{"type":"apps","id":"${app}"}},
#     "betaTester":{"data":{"type":"betaTesters","id":"${tester}"}}}}}
#   JSON
#
# Credentials: ASC_KEY_ID, ASC_ISSUER_ID, and the .p8 -- see
# Scripts/asc-jwt.rb.
#
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "asc-api: $*" >&2; exit 1; }

method="GET"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X) method="${2:?-X needs a method}"; shift 2 ;;
    -*) fail "unknown option: $1" ;;
    *) break ;;
  esac
done

path="${1:-}"
[ -n "$path" ] || fail "usage: $0 [-X METHOD] <path> [json|-]"
shift

case "$path" in
  https://*) url="$path" ;;
  /*) url="https://api.appstoreconnect.apple.com${path}" ;;
  *) fail "path must start with / or https://: ${path}" ;;
esac

body=""
if [[ $# -gt 0 ]]; then
  if [ "$1" = "-" ]; then body="$(cat)"; else body="$1"; fi
fi

token="$(Scripts/asc-jwt.rb)"

# --globoff because every filter and fields parameter in this API is
# spelled filter[email], and curl otherwise reads the brackets as a
# range to expand and refuses the URL.
#
# Status on its own line after the body, so a failed call can print what
# Apple said about it -- the errors carry a detail field worth reading.
args=(--silent --show-error --globoff --write-out '\n%{http_code}'
      --header "Authorization: Bearer ${token}" --request "$method")
if [ -n "$body" ]; then
  args+=(--header 'Content-Type: application/json' --data "$body")
fi

response="$(curl "${args[@]}" "$url")"
status="${response##*$'\n'}"
printf '%s\n' "${response%$'\n'*}"

case "$status" in
  2*) ;;
  *) fail "HTTP ${status} from ${method} ${url}" ;;
esac
