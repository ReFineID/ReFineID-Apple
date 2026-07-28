# Recorded decisions

Decisions with dates and rationale. `Documentation/release-plan.md` controls scope and
security behavior; this file records the concrete values chosen under it.

## 2026-07-29 An ended NFC field is an absent token

The iOS token session maps only `CardOperationError.sessionUnavailable`
to CryptoTokenKit `tokenNotFound` (`-7`). That error means the token
instance minted for the previous system NFC field no longer has a card
behind it, so a retry can open a replacement field and mint a fresh
instance. PACE refusal, APDU timeout, secure-messaging failure and card
status errors remain communication failures; none may request a retry
under the fiction that the card was merely absent.

This was measured on an `admin.iki.fi` client-certificate login. The
token completed PACE at `21:55:55.359`, Apple ended its field at
`21:55:56.625`, and Safari asked for the signature only at
`21:55:59.766`, after the holder had answered the system certificate
consent. The extension returned `-7` in 3.2 ms. A fresh token on the next
attempt completed PACE, PIN1 verification and ECDSA signing in 1.107 s.

The certificate-consent UI is outside the extension. It can therefore
consume the first field before the signature request exists. Once Safari
remembers that choice, a repeat reaches the signature while its fresh
field is alive. The extension cannot preselect or accept the certificate.

## 2026-07-29 A mismatched card family is refused before PACE

An iOS prime is looked up by the SHA-256 fingerprint of the card's ATR.
When a registered generation-05 identity was offered a generation-04
card, the extension recorded a prime miss and returned `tokenNotFound`
without one APDU. It did not start PACE and did not send the stored card
access number or PIN1 to the other card.

This is a card-family guard, not proof of a unique physical card. Cards
of the same model can share an ATR, and the unique printed serial is not
available until after PACE. Code and user-facing claims must preserve
that distinction.

## 2026-07-29 Resolve known issuing CAs before reading the card

Identity creation reads the authentication leaf and card serial once. It
resolves the leaf's issuing CA from the app's bundled public FINEID
intermediates first, using an exact normalized issuer-to-subject match, and
reads the issuing file from the card only when this build has no match.

The normal G4E path previously selected the master file, selected EF.4336,
and issued nine protected READ BINARY commands for the same public
intermediate bundled by this change. A device trace measured those eleven
exchanges at about 678 ms. They add no freshness or card binding: the leaf
names its issuer, and the intermediate is a public CA certificate valid from
2021 to 2041. The G4E resource is the DER certificate served by DVV's
certificate-authority API, stored as PEM; its SHA-256 fingerprint is
`AAD1BEAC4696102A88BF9D518D64F8B014F78F9B152579C959998313197924D7`.

This is a preference, not an assumption. Unknown future issuers still take
the existing on-card fallback and are stored with the prime, so every later
login remains independent of the app bundle and does no certificate read.

## 2026-07-28 Authentication observes PIN1, not unrelated credentials

Normal identity minting does not read any retry counter. Reader authentication
reads one side-effect-free PIN1 retry result immediately before VERIFY PIN1 and
fails closed when it is unreadable, blocked, or below three attempts. It does
not read PIN2 or PUK: authentication cannot consume either credential, and
those APDUs only added field time and unrelated failure modes. The
all-credential probe remains an explicit status and diagnostics operation.

The system-driven iPhone NFC field reads no retry counter. Hardware traces
showed that even one diagnostic APDU can spend the remainder of its field
deadline after PACE. That path therefore uses only PIN1 the holder explicitly
stored; a confirmed rejection removes the automatic identity before it can be
offered again.

Once a card accepts a freshly entered PIN1, the token extension may retain a
zeroizing copy for that complete card serial until the extension process exits.
This avoids repeated entry while retaining a fresh retry-floor probe and actual
VERIFY for every reader signature. There is no timer and no 5/5/5 prerequisite.

The first confirmed PIN1 rejection clears that process memory. When the token is
an automatically configured iOS identity, it also deletes stored PIN1, every
prime belonging to that physical card, and the exact CryptoTokenKit
registration. Only the card's PIN rejection or blocked response triggers that
revocation; radio loss, PACE failure, bad signature shape, and TLS failure do
not.

## 2026-07-28 A card directory replaces the single stored number

Every known card is an entry -- serial, model key, display name, and
its card access number -- newest first, stored as one JSON blob in the
keychain and mirrored to a second driver-configuration entry on macOS.
A sealed card is anonymous before PACE, so the driver filters
candidates by the ATR historical bytes and tries them newest first;
between different card models the filter is complete. Add proves a
typed number against the present card before recording the pair. The
single unbound number remains as the last candidate and the status
row's quick entry path.

## 2026-07-28 The card access number is holder-visible

The store's original rule -- never hand a stored value back for display
-- treated the card access number like PIN1. They are not alike: the
number is printed on the card face, has no retry counter, and exists to
stop remote skimming, not to be hidden from its holder. The Card menu's
manager window therefore shows, replaces and forgets the stored number
without requiring a card to be present. PIN1 remains write-only, and
the number still never enters logs, traces or diagnostics exports.

Storing and reading the number are likewise ungated -- no Face ID,
Touch ID or passcode prompt -- which amends the 2026-07-27 gate
decision to cover PIN1 alone. What remains is the storage boundary:
the item stays `WhenUnlockedThisDeviceOnly` and non-synchronizable,
so the number is never written into a backup and never sent to
iCloud.

## 2026-07-28 Stored PIN1 is directly available to the iOS token extension

The fifteen-minute software signing window is removed from the iOS
contactless path. If the holder explicitly stores PIN1, the token extension
reads it for each system-driven signature without requiring the containing
app to be opened again.

The old window was not a dependable security boundary. Safari can launch
the extension independently, and the extension has no reliable interface
in which to ask the app to reopen a window before CryptoTokenKit's roughly
two-second NFC operation expires. In practice the window converted a
correctly primed card into an unavailable identity after fifteen minutes
and produced repeated card/certificate/card prompts.

The stored item remains `WhenUnlockedThisDeviceOnly` and
non-synchronizable. The tradeoff is explicit: possession of an unlocked
phone plus the card can authorize a signature without reopening ReFineID.
The system certificate-consent UI remains outside the extension and cannot
be preselected by it.

## 2026-07-28 Status and diagnostics must not enumerate token identities

`SecItemCopyMatching` against the `com.apple.token` identity group is not a
passive readiness check on iOS. It can cause ctkd to create a token and
present the "Ready to Scan" sheet. The status screen was therefore capable
of starting the NFC operation it claimed only to report, and a diagnostics
capture could consume the field before a Safari test.

Status now observes already-published token IDs through `TKTokenWatcher`.
Diagnostics reports the typed application stores and watcher state, and
states that token keychain counts were intentionally not queried.

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
seconds later and has to find it. Two stores carry that handover, both in
CardCore: `PrimeStore` (the primed identity) and
`CardCredentialStore` (the explicitly stored CAN and optional PIN1).

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
two stores read as absent in the extension. Both fail open - the
credential store to "ask for PIN1", the prime to "not a contactless
card" - so the contact path behaves exactly as it always has. macOS has
no NFC slot to prime for, and adding a group there would widen the
reviewed allowlist in
`Scripts/inspect-archive.sh` for no working feature.

## 2026-07-28 Select the available card transport automatically

ReFineID reaches the card over a contact/PC-SC reader and, on iOS 26+,
over the phone's own NFC antenna. Native CryptoTokenKit mTLS over NFC was
proven end to end on device on 2026-07-25 (the card signs the TLS
CertificateVerify; the site returns HTTP 200), which removes the reason
to defer the contactless path.

There is no holder-facing transport preference. A connected card reader
is used when the platform presents it; otherwise an iPhone uses its NFC
slot. A switch that merely restates physical availability creates stale
state and can make a working card appear broken. macOS has no NFC
smart-card slot (`API_UNAVAILABLE(macos)`), so its available transport is
necessarily contact.

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
