#!/usr/bin/env bash
#
# Build and install the PKCS#11 bridge to /usr/local/lib on this Mac.
#
# /usr/local/lib is the production home because it sits inside
# ssh-agent's default PKCS#11 provider allowlist (/usr/lib* and
# /usr/local/lib*); a module anywhere under $HOME is refused by
# ssh-add unless the agent is started with an explicit -P override.
# /usr/lib itself is sealed by SIP. The installed name matches the
# Linux module (librefineid_pkcs11.so) so consumer documentation and
# SunPKCS11 configuration read the same on both platforms.
#
# The library's install name is rewritten to its installed path and
# the bundle is re-signed ad hoc, since install_name_tool invalidates
# the build signature.
#
# Usage:
#
#   Scripts/install-pkcs11-macos.sh            build, install, verify
#   Scripts/install-pkcs11-macos.sh --check    verify what is installed
#
set -euo pipefail
cd "$(dirname "$0")/.."

library_name="librefineid_pkcs11.dylib"
install_dir="/usr/local/lib"
installed="${install_dir}/${library_name}"
package_dir="PKCS11Bridge"
built="${package_dir}/.build/release/libPKCS11Bridge.dylib"
staged="${package_dir}/.build/release/${library_name}"

fail() { echo "install-pkcs11-macos: $*" >&2; exit 1; }
note() { echo "install-pkcs11-macos: $*"; }

# Lists the card keys through the installed module. A missing card is
# not a failure; the module is still installed correctly.
smoke_test() {
  note "smoke test: ssh-keygen -D ${installed}"
  if ssh-keygen -D "$installed" 2>/dev/null | sed 's/^/  /'; then
    note "card keys listed"
  else
    note "no card keys listed (no card inserted?); insert the card and run:"
    note "  ssh-keygen -D ${installed}"
  fi
}

if [[ "${1:-}" == "--check" ]]; then
  [[ -f "$installed" ]] || fail "nothing installed at ${installed}"
  codesign --verify "$installed" || fail "signature verification failed"
  note "installed: $(ls -l "$installed")"
  smoke_test
  exit 0
fi

note "building release"
(cd "$package_dir" && swift build -c release)
[[ -f "$built" ]] || fail "build produced no ${built}"

note "staging ${library_name} with production install name"
cp "$built" "$staged"
install_name_tool -id "$installed" "$staged"
codesign --force --sign - "$staged"
codesign --verify "$staged" || fail "staged library failed signature verification"

note "installing to ${installed}"
if [[ -w "$install_dir" ]]; then
  install -m 0755 "$staged" "$installed"
else
  sudo install -d -m 0755 "$install_dir"
  sudo install -m 0755 "$staged" "$installed"
fi

note "installed: $(ls -l "$installed")"
smoke_test
note "done. ssh usage: ssh -o PKCS11Provider=${installed} user@host"
