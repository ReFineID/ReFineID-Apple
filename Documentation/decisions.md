# Recorded decisions

Decisions with dates and rationale. `Documentation/release-plan.md` controls scope and
security behavior; this file records the concrete values chosen under it.

## 2026-07-27 Split the CryptoTokenKit driver into discovery and minting

Two app extensions, not one, because the two roles are mutually exclusive
in a single driver.

ctkd polls for a card using the select-identifier an extension declares in
`com.apple.ctk.aid`. A driver that declares none gives the daemon nothing
to select, so a contactless card is never surfaced and the system's
Ready-to-Scan sheet waits forever. Declaring the AID on the driver that
mints the token breaks the other half: ctkd then stops invoking that
driver even for the app's own registered slot, nothing is minted, and
`registerSmartCard` fails. Splitting the roles across separate extensions
with different class-ids is what made system-Safari login work at all.

- Minting: `fi.refineid.ReFineID.ctk`, `ReFineIDTokenExtension`, declares
  no AID.
- Discovery: `fi.refineid.ReFineID.discovery`,
  `ReFineIDDiscoveryExtension`, declares the AID and refuses every
  `createToken` with `tokenNotFound`.

The advertised AID is `A0000002471001`, the ICAO eMRTD LDS application. A
Finnish ID card implements it as a travel document, and it answers a
SELECT over the contactless interface before PACE has run. The PKCS#15
application answers `SW=6982` until PACE completes, so polling with it
would surface nothing.

The discovery extension ships on macOS too. There is no NFC smart-card
slot there, so it simply never gets used; keeping one target list for both
platforms is cheaper than a platform-conditional embed.

Entitlements: each half has its own files. `Config/DiscoveryExtension*`
grants the macOS sandbox and smart-card access and nothing else, because
that half reads no keychain item, holds no card session and stores
nothing. Sharing one file with the minting half would have handed it that
half's keychain group the moment the group was added, which is exactly
what happened next. `Scripts/inspect-archive.sh` checks the reviewed
entitlement allowlist for both binaries, and now also fails an archive in
which the AID is on the wrong extension. The iOS discovery file later
gained one keychain group, for one write - see "Where the diagnostics
trace lives" below.

## 2026-07-27 Where the diagnostics trace lives

The three binaries cannot see each other's logs. On iOS 26
`log stream --device` is gone, `log collect` fails, and the file
`TokenLog` writes sits in a container no other process may open, so a
failure inside `ctkd` is indistinguishable from any other failure.

`CardCore/ExtensionTrace` is the one shared sink: a bounded
(20 000-byte, oldest-half-dropped) generic-password item under service
`fi.refineid.trace`, `WhenUnlockedThisDeviceOnly` and
non-synchronizable, in the keychain group all three binaries share. The
app reads it on the diagnostics screen and through `--trace`.
`TokenLog` writes to it as well as to its own file, so there is one text
and two readers rather than two texts. `record` versus `append` is the
whole of the API split: inside a live contactless field the lines are
kept in memory, because a keychain round trip per APDU spends the two
seconds the field lasts on narrating itself.

Nothing secret is written. Sizes, INS bytes, status words, timings and
typed reasons only - never a PIN, a card access number, a serial or a
holder name (release plan section 4.3). VERIFY is redacted whole,
including its length, because that length is the padded PIN block's.
The instance identifiers that do appear are SHA-256 digests of an ATR or
a certificate, not serials.

This is what `Config/DiscoveryExtension-iOS.entitlements` gained a
keychain group for. That half still reads no prime and holds no card
session; it writes one line, saying that `ctkd` polled a card with our
AID at all. Without it, a login that failed before discovery and one that
failed at the mint look identical. The group is the app's own, so the
binary could in principle read the prime too - a second, dedicated group
cannot be addressed without hard-coding the team prefix in source. macOS
is left alone: it has `log stream`, and widening the reviewed allowlist
in `Scripts/inspect-archive.sh` for a diagnostic would be the wrong
trade.

## 2026-07-27 The biometric gate is in app code, not in the keychain item

PIN1 briefly carried a `SecAccessControl` with `.biometryCurrentSet`, on
the principle that policy enforced by the Security framework cannot be
talked past and policy in app code can. Two measurements moved it back.

The token extension reads PIN1 while signing a request Safari made, with
no interface to present a prompt over, so an item-level gate stalls the
flow the app exists for. And gating broke storage outright: a protected
item survives a delete that skips the authentication interface, the add
that follows fails as a duplicate, and a perfectly good PIN reads as
rejected. `CardCredentialStore.write` now falls back to `SecItemUpdate`
on `errSecDuplicateItem` and its `delete` no longer skips the interface,
which is the fix that part needed regardless.

So `Sources/App/CardCredentialGate` is the gate, and it is the only one:
every path that stores or drops a card access number or PIN1 goes through
it, and it is the single place that reads
`DebugBiometricBypass.isRequested`. That bypass is the one way past the
prompt, it exists for the UI tests on hardware where Face ID cannot be
answered programmatically, and it is inside `#if DEBUG` on both sides -
the flag string is not in a release binary at all. The weakening versus
an access control is real and is accepted here rather than left implicit.

## 2026-07-27 One keychain group for the app and its minting extension

The contactless path is a handover between two processes. The app primes
a card and writes what it read; the token extension is asked for a token
seconds later and has to find it. Three stores carry that handover, all in
CardCore: `PrimeStore` (the primed identity), `Pin1SigningWindow` (the
fifteen-minute PIN1 window) and `CardTransportStore` (the holder's
transport preference).

An app extension carries its own `application-identifier`, so by default
it addresses its own private keychain group and cannot see a single item
the containing app wrote. Left that way the extension finds no prime for
any card, `createToken` refuses with `primeMissing`, and no contactless
login is possible - silently, since a missing prime is indistinguishable
from a card that was never primed.

`Config/TokenExtension-iOS.entitlements` therefore grants exactly one
group, `$(AppIdentifierPrefix)fi.refineid.ReFineID` - the app's own. It is
also the FIRST entry of the app's array in
`Config/ReFineID-iOS.entitlements`, which is what makes the app's writes
land there: an item added without an explicit `kSecAttrAccessGroup` goes
to the first group of the writer's entitlement. Reordering that array
would silently move every write out of the extension's reach.

macOS is deliberately left alone. Its entitlements carry no keychain
group, so the app and the extension keep separate keychains there and the
three stores read as absent in the extension. All three fail open - the
transport preference to "every transport", the window to "ask for PIN1",
the prime to "not a contactless card" - so the contact path behaves
exactly as it always has. macOS has no NFC slot to prime for, and adding a
group there would widen the reviewed allowlist in
`Scripts/inspect-archive.sh` for no working feature.

## 2026-07-25 Support both card transports, with a user preference

ReFineID reaches the card over a contact/PC-SC reader and, on iOS 26+,
over the phone's own NFC antenna. Native CryptoTokenKit mTLS over NFC was
proven end to end on device on 2026-07-25 (the card signs the TLS
CertificateVerify; the site returns HTTP 200), which removes the reason
to defer the contactless path.

Both transports are user-disablable. They differ in cost rather than
capability: a reader is faster and needs no CAN, while NFC needs no
hardware but asks the holder to keep the card still for several seconds.
Disabling NFC also means never asking for a CAN. The preference is inert
on macOS, which has no NFC smart-card slot
(`API_UNAVAILABLE(macos)`), and it must be readable by the token
extension, which is a separate process.

Architecture and the four implementation rules that the NFC path must not
violate: `Documentation/card-transports.md`.

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
- Discovery extension: `fi.refineid.ReFineID.discovery` (added 2026-07-27;
  see the CryptoTokenKit split decision above)

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
