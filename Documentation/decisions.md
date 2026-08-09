# Recorded decisions

Decisions with dates and rationale. `Documentation/ios-product-plan.md`
controls iPhone scope. `Documentation/release-plan.md` controls
macOS scope and shared security behavior. This file records the concrete
values chosen under them.

## 2026-08-09 Built-in NFC ships in production on iPhone

The built-in NFC transport is a required production iPhone feature. Its
TestFlight and App Store builds ship the complete priming, registration,
discovery, and signing path. It is not debug-only and it is not future
work.

An observed unsolicited system "Ready to Scan" sheet while an unrelated
app was in the foreground is a ReFineID bug to diagnose. A valid fix may
narrow when the registered identity is requested or activated, but it must
preserve deliberate NFC setup and client-certificate authentication end to
end. Removing NFC, excluding it from a shipping configuration, or treating
the macOS-only NFC exclusion as an iOS product decision is not a fix.

The 2026-07-25 device exchange, recorded in the 2026-07-28 transport
decision below, proves native CryptoTokenKit mTLS over NFC through the TLS
`CertificateVerify` and HTTP 200. `Documentation/card-transports.md`
records the architecture. Apple's CryptoTokenKit and CoreNFC references in
`doc/references.md` prove the platform API surface; they do not decide this
product's shipping scope. This entry does.

## 2026-08-04 Card management and PIN2 signing enter scope, macOS first

The full credential set - activation, PIN1/PIN2 change, PUK unblock,
and PIN2 qualified signatures - is required on macOS, iPadOS and iOS;
macOS ships first, natively in Swift. The release plan's exclusions
are lifted accordingly, and the review gate the plan demanded for PIN2
signing is this entry and the hardware matrix items in TASKS.md.

The shape: CardCore carries the credential commands (VERIFY for both
PINs, CHANGE REFERENCE DATA, RESET RETRY COUNTER) as consume-once
noncopyable values, the qualified key joins MSE:SET behind an explicit
key parameter, and activation classifies the card by its own
certificate - issuance date authoritative, issuer name fallback,
refusal over guessing. The management window drives all of it behind
the same side-effect-free retry floor as authentication, with no
expert override. The CryptoTokenKit extension publishes the qualified
identity from live reader mints only, under its own constraint, with
PIN2 collected per signature and never cached; contactless primes
publish no qualified key, so the phone login path is untouched.

Chosen against a command-line tool (excluded as before) and against
direct in-app signing as the first resort: publishing through
CryptoTokenKit lets every system client request a qualified signature.
Direct in-app operations remain the fallback if hardware validation
shows ctkd cannot carry per-signature PIN2 semantics.

## 2026-08-01 The PACE suite stays fixed, now for a measured reason

`PaceCommand.securityEnvironment()` sends
id-PACE-ECDH-GM-AES-CBC-CMAC-256 over brainpoolP384r1 without asking
the card what else it takes. PACE is about three quarters of an NFC
login, so that assumption was worth testing rather than keeping.

EF.CardAccess was read from the card. It advertises that suite and
PACE-ECDH-CAM with the same domain parameter, and nothing else: no
integrated mapping, no smaller curve. The mapping Diffie-Hellman is
therefore unavoidable and brainpoolP384r1 is the only field on offer.
CAM is not a saving for a terminal that does not perform chip
authentication, which this one does not.

The suite stays fixed, and negotiation stays unbuilt: there is nothing
to negotiate with. `CardAccessFile` and the diagnostics probe remain,
because the next card generation is the thing that would change this
answer and re-asking should cost one hold rather than a rewrite.

## 2026-08-01 A set identity is the whole screen

Once an identity is set there is nothing left to configure, so nothing
about configuring it is shown. The setup header and the two credential
checkmarks go, leaving one `Identity` row with one mark, and the
destructive action reads `Forget identity`.

Before that state the screen has exactly one primary action: a filled,
full-width `Set identity` button in its own section, rather than a plain
row named after the minting mechanics. The credential rows collect, the
button commits, and Apple's NFC sheet owns everything after the tap.
This is the HIG shape for a setup flow -- at most one prominent button
per view, labelled for the outcome rather than the implementation.

Diagnostics is pinned under the content at the bottom of the screen. It
is development-only furniture, not a product feature, and it sits below
every product control instead of between them.

Confirmations use alerts, not confirmation dialogs. iOS presents a
confirmation dialog as a popover anchored to its source; the popover
form drops the cancel action, and it was measured landing across the
navigation bar far from the button that opened it.

## 2026-08-01 No gate stands in front of storing PIN1

The app-side biometric prompt guarded only the act of writing a PIN the
holder had just typed. The token extension reads the stored value
ungated -- it must, inside a two-second signing field -- so possession
of an unlocked phone plus the card already authorizes a signature, gate
or no gate. The card's own retry counter is the control that stops a
guessed PIN.

Removing it deletes a prompt, a passcode-missing failure mode, and the
`DebugBiometricBypass` flag that existed only to get UI tests past the
prompt on hardware where Face ID cannot be answered programmatically.
This supersedes the app-code half of the 2026-07-27 gate decision.

The keychain item is unchanged: `WhenUnlockedThisDeviceOnly`,
non-synchronizable, never displayed, never in a backup or iCloud.

## 2026-08-01 One NFC field primes and registers

Priming opened two consecutive system NFC fields: a Core NFC read for
PACE and the certificate, then a CryptoTokenKit slot that existed only
to mint and register. The holder read two sheets and paid two field
setups for one setup action.

Both now happen inside the one CryptoTokenKit field. Two bridges make
that work, and they replace the staged prime record the two-field design
used:

A registration mark in `PrimeStore`, written BEFORE the slot opens,
tells the extension's mint to publish metadata without taking a card
session, so the app keeps the card for PACE, the reads, and
`registerSmartCard`. Written after the slot opens it would lose the
race, which is why the staged record could not serve a single field.

`TokenDriver.awaitPrime` returns from before the split: `ctkd` asks for
a token the moment the card enters the slot, while PACE is still
running, so the mint waits up to five seconds for the prime rather than
missing it once and never asking again. The ceiling comes from a
measured 3.6 s prime, since cut by the bundled-issuer match of
2026-07-29.

An already-primed card skips the card I/O entirely and the whole hold is
the registration. The cross-field identity guard goes with the second
field: with one field there is no cross-field identity to guard, and the
record the extension reads is keyed by the live field's own ATR.

Proven on device 2026-08-01. One hold ran PACE, the certificate and
serial reads, and the registration: the prime reached the store on
`awaitPrime` attempt 13 (about 3.2 s of the five-second ceiling), the
mint read `registration=true` and took no card session, and
`createToken` returned in 3,103 ms. This also settles the question the
2026-07-28 build-16 trace left open: PACE inside a CryptoTokenKit field
completes when the app owns that field.

## 2026-08-03 iPad is supported, and asks the device rather than the build

The device family becomes iPhone and iPad. An iPad reaches the card the
only way it can, through a USB-C reader, which is a transport this app
already drives on macOS.

That required the near-field question to stop being a build-time
answer. `SupportedCardTransports` returned "yes" for anything that
imported CoreNFC and ran version 26 -- which iPadOS does, on hardware
with no antenna. An iPad holder was therefore offered a card setup that
could never complete: two fields to fill and a button that could only
ever stay grey. It now asks `TKSmartCardSlotManager.isNFCSupported`,
the one of the three conditions that differs between two devices
running the same binary.

A device with no antenna is told the one thing that helps -- connect a
reader and insert the card -- instead of being shown a setup form it
cannot use.

## 2026-08-03 Export compliance is declared as non-exempt

`ITSAppUsesNonExemptEncryption` is `true` in the app's Info.plist.

The app does not merely call the platform's cryptography: it implements
brainpoolP384r1, AES-CMAC secure messaging and the PACE handshake
itself, in Swift, in this repository. The authentication-only exemption
was available to argue for and is deliberately not taken. Declaring
non-exempt costs a self-classification report and an annual French
declaration; declaring exempt on a judgement call costs credibility we
would rather not spend, in a product whose whole subject is identity.

Stating it in the bundle rather than answering it per upload is the
point of the check in `inspect-archive.sh`: the answer belongs in
reviewed source, not in whatever somebody clicked at four in the
afternoon.

Declaring it is half the statement. App Store Connect refused the first
upload with error 90592 -- "the export compliance key value [] in the
app's Info.plist doesn't match the key value of the app's export
compliance documentation" -- because a `true` declaration is compared
against documentation filed for the app, and there was none. So
`ITSEncryptionExportComplianceCode` has to carry the code Apple issues
once that documentation is accepted, and until it does, nothing
uploads.

That is a deliberate wait rather than a workaround. The alternative
offered itself twice -- drop the key and answer the questionnaire per
build -- and was refused both times for the same reason the key exists.

`inspect-archive.sh` now fails locally when the declaration is `true`
and the code is absent. The same answer that took a full archive, an
export and several minutes of transfer to get from Apple takes about a
second here.

What was submitted, the cryptography it describes, and why the
authentication-only exemption was not taken:
`Documentation/export-compliance.md`.

## 2026-08-03 Diagnostics is a development tool, on both platforms

TestFlight is a shipped build. It reaches people who are not us, on
their own phones and Macs, with their own cards -- so it carries no
diagnostics screen, no capability probe, and no logging, exactly as
Release does not. Only Debug and Profile have them, and Profile is what
goes on a development device.

The exclusion is at file level rather than at a condition:
`EXCLUDED_SOURCE_FILE_NAMES` removes the diagnostics sources from the
app target in TestFlight and Release, so they are not compiled at all
rather than compiled into nothing. A `#if` that is wrong still ships;
a file that was never given to the compiler cannot.

Verified by building both and reading the binaries rather than trusting
the settings. In TestFlight for iOS and Release for macOS the app binary
contains no "Diagnostics", no "Card capabilities", no "EF.CardAccess",
and no "Clear diagnostic logs"; the token and discovery extensions
contain no message literal, no `fi.refineid.ReFineID:ctk` subsystem, and
no trace file path. The one `createToken` hit in an extension is
`tokenDriver:createTokenForSmartCard:AID:error:`, which is
CryptoTokenKit's own selector and not ours to remove.

## 2026-07-30 A shipped build says nothing

TestFlight and App Store builds carry no diagnostics and write no log of
any kind: no `os.Logger` line, no file in the extension container, no
line in the shared keychain trace. Debug and Profile are unchanged and
keep every instrument, because Profile is what goes on the phone during
development and the extension trace is still the only way to see inside
a process `ctkd` hosts.

The gate is `#if DEBUG`, which the project defines for Debug and Profile
and not for TestFlight or Release, applied at the sinks - ``TokenLog``
for the token extension, the new ``AppTrace`` for the app's own Core NFC
and status card channels, and the one `ExtensionTrace.append` in the
discovery driver. The 86 call sites are untouched.

Two things had to be measured rather than assumed:

`CardCore` never sees the condition. Xcode compiles the local package
with `-DSWIFT_PACKAGE` alone - not `DEBUG`, not the project's
`TESTFLIGHT` - so a guard inside `ExtensionTrace` would have removed the
trace from Profile as well, which is the one build that needs it. The
gate therefore lives in the targets that do get the condition, and
`ExtensionTrace` stays as it is. `ExtensionTrace.clear()` is left
reachable everywhere on purpose: never writing is the requirement, and a
shipped build must still be able to delete a buffer an earlier
development build left on the device.

An empty inlined function is not enough on its own. With a plain
`String` parameter the call disappears but the interpolation that built
its argument does not: about twenty trace fragments stayed in the
optimized binary. The messages are `@autoclosure` for that reason. The
cost is that a closure formed in a scope consuming a noncopyable value
makes Swift 6.3.3 report a copy of a noncopyable value at the `consume`
and call it a compiler bug; `TokenSession.signInField` takes the one
affected value into a `Bool` first.

Measured on the current source: the TestFlight and Release binaries
contain none of the trace literals and no reference to the extension log
file; the Profile token extension still contains 23. `Scripts/inspect-archive.sh`
now fails an archive in which any of them reappear, and rejects the
Profile bundle when pointed at it.

## 2026-07-29 Every connected reader card is published; Safari selects

CryptoTokenKit creates and retains a live token for every supported card
inserted in a connected reader. Every live token publishes its signed
authentication certificate and key. ReFineID does not rank cards, retain a
preference, or implement a second certificate picker.

Safari owns certificate selection. A live iOS 26.5 test with two tokens proved
that Safari renders the signed X.509 subject in its client-certificate picker,
even when the CTK certificate and key carry distinct `kSecAttrLabel` values.
Two cards issued to the same person can therefore have identical-looking rows;
cards issued to different people show their different certificate subjects.
ReFineID must not alter the signed certificate to change that text.

This is the smallest and most compatible boundary: CryptoTokenKit publishes
the identities, Safari selects one, and the app reports only whether one or
several usable USB-C reader tokens are live.

## 2026-07-29 Engineering diagnostics are not product functionality

The interactive diagnostics report, shared-trace controls, and support
disclosure row are present in Debug and Profile builds only. TestFlight and
Release compile the entry points out and exclude `DiagnosticsView`,
`DiagnosticsSnapshot`, `DiagnosticsClipboard`, and `StatusSupportSection`
from the application target. The ordinary card status and explicit
"Forget this card and identity" recovery action remain product features.

This is a build boundary rather than a hidden switch. An App Store binary
must not contain dormant engineering screens, while the optimized Profile
configuration used for live card development still needs the same
instruments that made the NFC path measurable.

## 2026-07-29 A reader mint supersedes every ReFineID NFC identity

On iOS, successfully minting a token for a card in a connected reader
removes every stored ReFineID contactless prime and synchronously
unregisters every persistent ReFineID smart-card identity before the
reader mint returns. Inserting a reader and a usable card is an explicit
global transport choice within ReFineID; Safari must not also wake the
phone's NFC field. Apple and third-party identities are untouched.

The first implementation scoped removal to the reader card's printed
serial. A live trace disproved that boundary: the USB reader published an
RSA card while an EC card remained registered for NFC, so Safari still
chose NFC. The transport decision is therefore independent of card
serial, ATR, and key profile. Stored CAN, PIN1, card-directory entries,
NFC primes, and ReFineID Safari registrations are removed; the newly
minted live reader token remains published. If the holder later wants NFC
again, "Set identity" performs the deliberate one-time contactless setup
again.

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

The v3.1 identity cards cross DVV's 17 February 2022 citizen-certificate
hierarchy change. Earlier cards name `VRK Gov. CA for Citizen Certificates -
G3`, not G4R or G4E. That public intermediate is the exact DER returned by
`https://dvv.fineid.fi/api/v1/cas/103/certificate`, stored as PEM; its
official SHA-256 fingerprint is
`39A835B14B6B6313F778371C79CB434DD518C8FD325B749D9BE669DFF20384E8`.

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

- Minting: `fi.refineid.ReFineID.token`, `ReFineIDTokenExtension`, declares
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

An app-side gate (`Sources/App/CardCredentialGate`) then stood in front
of PIN1 storage until 2026-08-01, when it was removed; see the entry
below. The keychain-item half of this decision stands: neither item
carries a `SecAccessControl`, for the reasons measured above.

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
- Token extension: `fi.refineid.ReFineID.token`
- Discovery extension: `fi.refineid.ReFineID.discovery` (added 2026-07-27;
  see the CryptoTokenKit split decision above)

Apple requires an embedded extension's identifier to be prefixed by the
containing app's identifier.

The token extension used the provisional `.ctk` suffix during development.
It moved once to the final `.token` suffix on 2026-07-29, before release.
On the development phone, an attribute query could see the provisional
provider's identity while Apple's exact certificate-reference query
returned no references after token access had been denied. iOS exposes no
API or Settings control to inspect or reset that decision. The final
identifier is stable; changing it is not a runtime recovery mechanism.

The P0 task remains open until all identifiers are registered as explicit
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

## 2026-08-07 The plist answers Apple's question, not the EAR's

`ITSAppUsesNonExemptEncryption` is `false` until the ANSSI attestation
exists, then `true` together with the code Apple issues.

Amends the 2026-08-03 entry above. Apple's key does not record the EAR
analysis: by its definition, `false` states the app "only uses forms of
encryption that are exempt from export compliance documentation
requirements". App Store Connect proved that is this app's position
twice on one day -- its API refuses App Encryption Documentation for
standard published algorithms outside the French store, and it rejects
an upload declaring `true` without a code, mid-transfer, with 90592. A
`true` nobody is allowed to document is not credibility; it is a failed
upload.

The reviewed-source point stands: the answer stays in the bundle, and
`inspect-archive.sh` still refuses `true` without a code.
