#!/usr/bin/env bash
#
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Drive an App Store submission through the App Store Connect API,
# without fastlane or any other dependency.
#
# The pieces below the web UI are a handful of REST calls, and doing
# them by hand leaves no record of what was done. This composes them
# into named steps on top of Scripts/asc-api.sh (the authenticated
# transport) and Scripts/asc-jwt.rb (the token). It knows the app by
# its bundle id and nothing secret; the key and issuer ids come from
# the environment, or from ~/.appstoreconnect/env when present.
#
# It is deliberately idempotent: ensure-version finds an existing
# version before creating one, so a re-run after a partial failure
# does no harm.
#
# Usage:
#
#   Scripts/asc-release.sh app-id
#       Print the app's App Store Connect id.
#
#   Scripts/asc-release.sh ensure-version <ios|macos> <versionString>
#       Print the version's id, creating it if it does not exist.
#
#   Scripts/asc-release.sh attach-build <ios|macos> <versionString> <buildNumber>
#       Attach a processed build to the version.
#
#   Scripts/asc-release.sh state
#       Print every version, its platform, state, and attached build.
#
# The build must have finished processing (state VALID) before it can
# be attached; watch it with `state` after an upload.

set -euo pipefail
cd "$(dirname "$0")/.."

[ -f "$HOME/.appstoreconnect/env" ] && . "$HOME/.appstoreconnect/env"

readonly BUNDLE_ID="fi.refineid.ReFineID"
API="Scripts/asc-api.sh"

fail() { echo "asc-release: $*" >&2; exit 1; }

# The value of a JSON path from stdin, or empty. Keeps the callers
# free of inline python and its quoting.
json() {
    python3 -c 'import json,sys
d=json.load(sys.stdin)
cur=d
for k in sys.argv[1:]:
    if isinstance(cur,list):
        i=int(k); cur=cur[i] if 0<=i<len(cur) else None
    elif isinstance(cur,dict): cur=cur.get(k)
    else: cur=None
    if cur is None: break
print("" if cur is None else cur)' "$@"
}

# The two-letter platform name the API wants.
api_platform() {
    case "$1" in
        ios) echo "IOS" ;;
        macos) echo "MAC_OS" ;;
        *) fail "platform is ios or macos, not '$1'" ;;
    esac
}

app_id() {
    "$API" "/v1/apps?filter[bundleId]=${BUNDLE_ID}&fields[apps]=bundleId" \
        | json data 0 id
}

# Prints the id of the version for a platform and version string,
# creating it when absent.
ensure_version() {
    local platform version app existing
    platform=$(api_platform "$1")
    version="$2"
    app=$(app_id)
    [ -n "$app" ] || fail "app ${BUNDLE_ID} not found on this account"
    existing=$(
        "$API" "/v1/apps/${app}/appStoreVersions?filter[platform]=${platform}&filter[versionString]=${version}&fields[appStoreVersions]=versionString" \
            | json data 0 id
    )
    if [ -n "$existing" ]; then
        echo "$existing"
        return
    fi
    local body
    body=$(printf '{"data":{"type":"appStoreVersions","attributes":{"platform":"%s","versionString":"%s"},"relationships":{"app":{"data":{"type":"apps","id":"%s"}}}}}' \
        "$platform" "$version" "$app")
    "$API" -X POST "/v1/appStoreVersions" "$body" | json data id
}

# Attaches a processed build, by its build number, to a version.
attach_build() {
    local platform version number vid app bid
    platform=$1
    version=$2
    number=$3
    vid=$(ensure_version "$platform" "$version")
    [ -n "$vid" ] || fail "could not resolve the version"
    app=$(app_id)
    bid=$(
        "$API" "/v1/builds?filter[app]=${app}&filter[version]=${number}&fields[builds]=version&limit=1" \
            | json data 0 id
    )
    [ -n "$bid" ] || fail "build ${number} not found; has it finished uploading?"
    "$API" -X PATCH "/v1/appStoreVersions/${vid}/relationships/build" \
        "{\"data\":{\"type\":\"builds\",\"id\":\"${bid}\"}}" >/dev/null
    echo "attached build ${number} to ${platform} ${version}"
}

# Prints every version with its platform, state, and attached build.
state() {
    local app
    app=$(app_id)
    "$API" "/v1/apps/${app}/appStoreVersions?fields[appStoreVersions]=versionString,platform,appStoreState,build&include=build&fields[builds]=version&limit=50" \
        | python3 -c 'import json,sys
d=json.load(sys.stdin)
builds={i["id"]:i["attributes"]["version"] for i in d.get("included",[]) if i["type"]=="builds"}
for v in d.get("data",[]):
    a=v["attributes"]
    rel=v.get("relationships",{}).get("build",{}).get("data")
    b=builds.get(rel["id"]) if rel else None
    print("  %-7s %-10s %-24s build=%s" % (a["platform"], a["versionString"], a["appStoreState"], b or "-"))'
}

# Pushes a platform version's localizations from Metadata/ - the
# description, keywords, promotional text, and the support and
# marketing URLs - creating a locale that is absent and updating one
# that is present. Each locale is a directory under Metadata/, and the
# description is the platform's own (description-macos.txt,
# description-ios.txt), so a Mac and an iPhone read differently while
# sharing everything else. The body goes over stdin, so a description's
# newlines and non-ASCII letters reach the API intact.
push_metadata() {
    local platform version vid locmap dir locale existing payload
    platform=$1
    version=$2
    vid=$(ensure_version "$platform" "$version")
    [ -n "$vid" ] || fail "could not resolve the version"
    locmap=$("$API" "/v1/appStoreVersions/${vid}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale&limit=50")
    for dir in Metadata/*/; do
        locale=$(basename "$dir")
        [ -f "${dir}description-${platform}.txt" ] || continue
        existing=$(printf '%s' "$locmap" | LOCALE="$locale" python3 -c '
import json,os,sys
loc=os.environ["LOCALE"]
d=json.load(sys.stdin)
print(next((l["id"] for l in d.get("data",[]) if l["attributes"]["locale"]==loc), ""))')
        payload=$(PLATFORM="$platform" LOCALE="$locale" VID="$vid" EXISTING="$existing" python3 - <<'PY'
import json, os
p, loc, vid, existing = (os.environ[k] for k in ("PLATFORM", "LOCALE", "VID", "EXISTING"))
def read(f):
    return open(f, encoding="utf-8").read().strip() if os.path.exists(f) else None
base = "Metadata/" + loc
cfg = dict(x.strip().split("=", 1) for x in open("Metadata/config") if "=" in x)
attrs = {
    "description": read("%s/description-%s.txt" % (base, p)),
    "keywords": read(base + "/keywords.txt"),
    "promotionalText": read(base + "/promotional_text.txt"),
    "supportUrl": cfg.get("support_url"),
    "marketingUrl": cfg.get("marketing_url"),
}
attrs = {k: v for k, v in attrs.items() if v}
if existing:
    body = {"data": {"type": "appStoreVersionLocalizations", "id": existing, "attributes": attrs}}
else:
    attrs["locale"] = loc
    body = {"data": {"type": "appStoreVersionLocalizations", "attributes": attrs,
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}
print(json.dumps(body))
PY
)
        if [ -n "$existing" ]; then
            printf '%s' "$payload" | "$API" -X PATCH "/v1/appStoreVersionLocalizations/${existing}" - >/dev/null
            echo "  ${locale}: updated"
        else
            printf '%s' "$payload" | "$API" -X POST "/v1/appStoreVersionLocalizations" - >/dev/null
            echo "  ${locale}: created"
        fi
    done
}

cmd="${1:-}"
shift || true
case "$cmd" in
    app-id) app_id ;;
    ensure-version) ensure_version "$@" ;;
    attach-build) attach_build "$@" ;;
    metadata) push_metadata "$@" ;;
    state) state ;;
    *) fail "unknown command '${cmd}'; see the header for usage" ;;
esac
