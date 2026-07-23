# Recorded decisions

Decisions with dates and rationale. `Documentation/release-plan.md` controls scope and
security behavior; this file records the concrete values chosen under it.

## 2026-07-22 iOS core: minimal pure-Swift Safari driver

The Rust core remains the reference oracle for differential testing and
the engine for future heavy flows (in-app NFC login with PACE/SM, the
relay), which move to v1.x or later. The same minimal Swift driver on
CardCore is the macOS product's M2 card core: one driver, two
platforms.

## 2026-07-22 Calendar versioning

`YY.M.D` version, ten-minute-bucket build number, tags carry the exact build
number. Full scheme: release plan, "Calendar versioning".

Stamped **manually at release** via `Scripts/stamp-version.sh`, deliberately
not a build phase: automatic stamping would churn the version number in
version control on every dev build. The script is present for release
automation; dev builds keep the last release's committed version. The
`v0.9.x` git tags are informal milestone markers, separate from the
calendar release/tag scheme.

## 2026-07-22 Bundle identifiers (decided; registration pending)

- Application: `fi.refineid.ReFineID`
- Token extension: `fi.refineid.ReFineID.ctk`

Apple requires an embedded extension's identifier to be prefixed by the
containing app's identifier.

The P0 task remains open until both identifiers are registered as explicit
App IDs on the release team.

## 2026-07-22 Minimum supported macOS: 26.0

Matches the only hardware evidence the project can currently produce.
Smallest possible v1.0 test matrix; every additionally supported major
version would need its own hardware-matrix pass. Lowering later is possible;
raising after release is disruptive.

## 2026-07-22 Entitlements (complete list, per target)

Application (`Config/ReFineID.entitlements`):

- `com.apple.security.app-sandbox` - App Store requirement
- `com.apple.security.smartcard` - the status window reads retry counters
  side-effect-free.

Token extension (`Config/TokenExtension.entitlements`):

- `com.apple.security.app-sandbox` - extensions are sandboxed; also required
  for the App Store.
- `com.apple.security.smartcard` - the CryptoTokenKit extension talks to the
  card.

No other entitlement is approved. `Scripts/inspect-archive.sh` fails the
archive if any other entitlement appears.

## 2026-07-22 Source layout

- `CardCore/` is a local Swift package (platform-independent protocol model;
  no UI, no CryptoTokenKit). The app and extension consume its library
  product.
- `Tests/CardCoreTests/` is a native unit-test-bundle target in the Xcode
  project rather than a package test target: one committed scheme then runs
  the same tests locally and in Xcode Cloud without relying on package
  testable resolution, which proved unreliable under `xcodebuild` with a
  hand-maintained scheme. Tests exercise the package's public API only.
- The Xcode project is hand-maintained (`objectVersion 77`, folder-
  synchronized groups). No project generator is used at any point.
