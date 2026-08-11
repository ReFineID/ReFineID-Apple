#!/usr/bin/env bash
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
    if isinstance(cur,list): cur=cur[int(k)]
    elif isinstance(cur,dict): cur=cur.get(k)
    else: cur=None
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

cmd="${1:-}"
shift || true
case "$cmd" in
    app-id) app_id ;;
    ensure-version) ensure_version "$@" ;;
    attach-build) attach_build "$@" ;;
    state) state ;;
    *) fail "unknown command '${cmd}'; see the header for usage" ;;
esac
