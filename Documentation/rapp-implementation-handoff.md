# RAPP Apple implementation handoff

Status date: 2026-08-16

This document is the implementation handoff for Remote Authorization Proxy
Protocol (RAPP) support in ReFineID on Apple platforms. It describes what is
present in this repository, where the protocol authority lives, what has been
measured, and what the next agent must do. It is not a security approval or a
claim that RAPP is production-ready.

## Protocol authority

The shared Rust repository is the protocol and state-machine authority:

- `../ReFineID/docs/protocol/rapp-v26.8.16.85.md`
- `../ReFineID/docs/protocol/rapp-state-machine-v26.8.16.85.yaml`
- `../ReFineID/crates/refineid-lib-core/src/rapp/`

The exact Rust source revision defining the ABI of the committed Apple
XCFramework is:

- `ReFineID/ReFineID@7506979dbdf479bf0d20571c104fe36722bbe24c`

That revision is pushed to the archived source repository. Do not regenerate
or replace the XCFramework from an uncommitted Rust worktree.

Do not independently redefine RAPP framing, transitions, role constraints,
failure policy, or cryptography in Swift. Change the Rust protocol/model first,
make its tests pass, regenerate the Apple binding, and then adapt the Apple
integration.

Important invariants already represented in the implementation are:

- The phone is the authorizer and retains CAN, PIN 1, and PIN 2.
- The requester receives operation results, not card credentials.
- Every operation requires an explicit authorizer decision.
- One authenticated protocol violation revokes the pairing immediately. There
  is no two-strike policy.
- Invalid card credentials, authenticated protocol anomalies, and ambiguous
  card completion are fail-stop events.
- Card activation and PIN management are not remotely exposed in RAPP 0.1.

The presently supported remote operation families are card status, browser
authentication, and qualified document signing.

## Generated Rust boundary

`CardCore/Artifacts/ReFineIDRappFFI.xcframework` is deliberately committed.
It contains arm64 slices for macOS, iOS device, and iOS Simulator. Intel macOS
is intentionally unsupported.

`CardCore/Sources/ReFineIDRapp/ReFineIDRapp.swift` is the generated Swift
binding. `CardCore/Package.swift` exposes the generated Swift target and binary
artifact to CardCore.

Regenerate both from the Apple repository root with:

```sh
swift Scripts/apple-app-store-connect-release-manager.swift rapp-bindings
```

The command expects the Rust repository at `../ReFineID`. The generated files
must be committed together with the Rust revision that defines their ABI. Do
not hand-edit generated bindings or leave a regenerated XCFramework untracked.

The static libraries are currently about 55 MB per slice. GitHub accepts them
but warns because they exceed its recommended 50 MB size. They remain below
GitHub's 100 MB hard file limit. If artifact distribution changes later, first
provide a reproducible, authenticated fetch/build path before removing them
from Git.

## CardCore RAPP layer

The handwritten Swift integration is under `CardCore/Sources/CardCore/`:

- `RappPlatformPrimitives.swift` provides Apple cryptographic and persistence
  primitives required by the generated core.
- `RappDeviceVault.swift` and `RappDeviceVault+Bindings.swift` store device and
  pairing material using the Apple security boundary.
- `RappPairCatalog.swift` tracks paired peers and the selected pair.
- `RappPairingCoordinator.swift` drives the pairing ceremony.
- `RappClosureFrameTransport.swift` adapts framed RAPP traffic to an Apple
  transport without moving protocol logic out of Rust.
- `RappConnectionCoordinator.swift` owns connection-level lifecycle.
- `RappSessionDriver.swift` drives one authenticated RAPP session.
- `RappOperationDriver.swift` drives operation request/authorization/result
  lifecycle.
- `RappCardOperationMapping.swift` maps Apple card operations to RAPP operation
  kinds and results.
- `RappPersistentRequesterClient.swift` provides the requester-facing client
  used by persistent token operations.

`PersistentCardRelay.swift` is connected to this layer. Keep transport and
card-operation effects outside the Rust state machine, but let Rust decide
which transition and output are legal.

## Application wiring

The application layer is under `Sources/App/`:

- `RappPairingUI.swift` presents QR pairing and visible paired status.
- `RappAuthorizationInbox.swift` serializes holder-visible authorization
  decisions on the phone.
- `RappNfcCardExecutor.swift` performs authorized card work through the normal
  NFC/card code paths.
- `RappPhoneProxyDispatcher.swift` dispatches authenticated remote requests to
  the phone authorizer.
- `PhonePersistentTokenRelay.swift` carries the phone side of persistent token
  requests and now enters RAPP rather than a credential-bearing shortcut.
- `MacPersistentTokenRegistry.swift` connects macOS requester registration to
  the selected RAPP pair.
- `PersistentTokenDriver.swift` connects CryptoTokenKit requester work to the
  RAPP client.
- `ReFineIDApp.swift`, `ReaderIdentityRootView.swift`, and `StatusView.swift`
  expose pairing and RAPP state in the existing application UI.

Remote document signing is wired through `DocumentSigner.swift`,
`AsicSigner.swift`, and `DocumentSigningView.swift`. The requester does not ask
for or retain PIN 2. The phone authorizer collects PIN 2, performs the card
operation, and returns the operation result. The Mac verifies the returned PDF
or ASiC-E result locally before presenting it as successful.

Pairing selection is persisted device-only. Pairing teardown is durable and is
not automatically repaired after a fail-stop event. A holder must pair again.

## Verified evidence

The following was measured before this handoff:

- `cargo test -p refineid-lib-core` passes in the Rust repository, including
  RAPP formal-state, interoperability, and operation-lifecycle tests.
- The formal transition tests prove state, event, and role legality and exact
  ordered emitted-action equality against every role-qualified YAML rule.
- `swift build --package-path CardCore` passes.
- The ReFineID Xcode scheme builds for macOS and generic iOS arm64.
- 510 Apple unit tests in 82 suites pass on macOS. The focused RAPP adapter
  suite drives requester and proxy pairing through the generated Rust bridge,
  persists both pair records, verifies transport closure, selects the requester
  pair, and proves that one revocation durably removes it from active and
  selected state. It also drives browser authentication through explicit
  prerequisite inspection and approval, proves exactly one card command,
  verifies durable result erasure after the authenticated acknowledgment, and
  proves that a credential rejection durably revokes both peers without another
  card execution. It also proves document signing executes exactly once and
  erases its retained result only after the authenticated acknowledgment. Its
  terminal-path matrix covers user denial, retry-policy refusal, card removal
  before transmit, and ambiguous card completion with exact prerequisite,
  approval, card-command, and transport-close counts. It exhaustively
  round-trips supported card profiles and signature algorithms through the
  Apple mapping layer.
- The RAPP vault's macOS listing path is measured against the file keychain:
  macOS rejects a bulk `match all` query that requests both attributes and
  secret data with `errSecParam`. The vault therefore enumerates account
  attributes and loads each record through the supported single-item query.
  The same 510-test run covers this persistence and enumeration path.
- All 40 `VirtualIDCardUITests` GUI cases passed on an iPhone 17 Pro iOS 26.5
  Simulator in bounded batches. They cover card-state routing, factory and
  partial activation UI, all PIN operations, retry recovery, signing success,
  signing rejection, retry-floor refusal, ambiguous/lost responses, card
  removal, injected faults, localization, and accessibility.
- The Finnish and Swedish localization smoke tests establish a registered
  Virtual ID Card through the reviewer-visible GUI and pass. The Finnish text
  clipping audit also passes after making the shared Sign action grow with its
  localized, Dynamic Type-sized label.
- Real-card setup, priming, and Safari UI-test classes now require
  `TEST_RUNNER_REFINEID_REAL_CARD_TESTS=1`. Default simulator and Xcode Cloud
  runs skip them instead of waiting for hardware or consuming a retry.
- A current Debug application was installed and launched on the cabled
  development iPhone.
- A manual alpha path from macOS Safari through the iPhone and its NFC identity
  card succeeded earlier. Treat that as useful integration evidence, not a
  repeatable release qualification for the current commits.

The Virtual ID Card uses the real UI and operation orchestration while
substituting card effects. It is not proof of Core NFC, physical card, local
network permission, CryptoTokenKit, or Safari system-sheet behavior.

## Known gaps and blockers

- Physical-device XCUITest currently stops while macOS asks Petri to authorize
  Enable UI Automation with Touch ID. Do not diagnose this as an application
  failure. Petri must clear the dialog in person.
- The latest committed RAPP consolidation has not had a fresh, recorded,
  end-to-end pair/status/browser-auth/signing run on two physical devices.
- `test-without-building` is unreliable with the current CoreSimulator because
  its temporary UI-test bundle is removed between invocations. Normal
  incremental `xcodebuild ... test` works.
- Irreversible credential and signing journeys should run as individual CI
  shards. Two signing fault journeys took 123.7 seconds together; each stays
  under the 120-second window when run separately.
- No independent cryptographic or protocol security review has approved RAPP
  for production.
- Cross-platform Android, Windows, Linux, and FreeBSD interoperability remains
  protocol intent, not implemented Apple evidence.

## Exact next step

1. Petri clears the pending Enable UI Automation Touch ID dialog.
2. Build and install the committed Debug app on the cabled iPhone.
3. Pair macOS and iPhone from a clean pairing state using the QR UI.
4. With a known activated card and correct CAN/PIN values, record one card
   status read, one Safari browser-authentication operation, and one harmless
   document signature. Verify that macOS never asks for PIN 1 or PIN 2 and that
   the phone asks for explicit authorization.
5. Repeat one operation after intentionally removing the card, not after
   intentionally entering a wrong credential. Confirm fail-stop teardown and
   manual re-pairing. Do not spend a real credential retry without Petri's
   explicit approval.
6. Archive the result bundle and update this document with exact build, device,
   OS, and commit identifiers before making a TestFlight or production-readiness
   claim.

## Commit boundary

The initial Apple RAPP implementation was committed on `main` as:

- `cf02443` - Add RAPP Swift protocol runtime
- `f05c4d8` - Integrate RAPP authorizer and requester flows
- `d987e71` - Make hardware UI tests explicit opt-in

All three were pushed to `origin/main` before this handoff was written.
