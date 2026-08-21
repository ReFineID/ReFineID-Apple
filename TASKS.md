# Apple release task list

Last reviewed: 2026-08-21

Completed work is removed. This file contains only concrete outcomes that are
still required for an Apple beta, App Store release, or the next protocol
milestone.

## Status, 2026-08-21: the iPhone MVP shape is implemented

The first App Store release is an iPhone MVP on iOS 26
(Documentation/decisions.md, 2026-08-21), and its shape is implemented
and committed on `main` at `620e54a` - 19 commits ahead of
`origin/main` (`31cbeda`), not yet pushed.

What ships: one-step NFC priming and Safari login, document signing
and checking, PIN changes, USB-C reader signing, and the demonstration
mode, whose virtual card now arrives already activated. What is gated
out of TestFlight and Release: the remote card (`REFINEID_REMOTE_CARD`
- pairing, requester, phone-holder relay, persistent-token
publication, the RAPP extension, and the Bonjour/local-network
declarations) and activation (`FEATURE_CARD_ACTIVATION` - an
unactivated card is shown a localized refusal instead of the form).
Shipping configurations build at floor 26, iPhone-only, with the `nfc`
required capability, from `Config/ReFineID-iOS-Store-Info.plist`;
Debug and Profile keep floor 16, both device families, and every gate
on. The archive inspector and `RappShippingConfigurationTests` enforce
all of it, and `Metadata/appstore.json` carries the matching reviewer
walkthrough and iPhone-only descriptions.

Verified 2026-08-21: iOS TestFlight, iOS Debug, and macOS TestFlight
all build clean; the store-shaped bundle carries exactly the reader
and discovery extensions, `MinimumOSVersion` 26.0, `UIDeviceFamily`
[1], `nfc`+`arm64`, and no Bonjour keys; the shipping-configuration
suite passes. The full non-UI suite passes 528 of 529 - the one
failure is a release blocker in section 0 and predates the gating
work.

App Store Connect: iOS 26.8.16 (114) awaits the guideline 2.1
demonstration video; the macOS (114) submission was withdrawn by the
owner on 2026-08-21. What remains before submission is exactly
section 0.

## Current RAPP handoff

This is the restart point for a fresh agent. Read
`Documentation/rapp-implementation-handoff.md` before changing RAPP. The
handoff describes the protocol boundary, generated-artifact provenance, Apple
extension topology, verified invariants, and known gaps in detail.

### Pushed baseline

- Rust protocol/core repository: `~/src/ReFineID` at
  `c745bb0cbab18b82877ddfa1143690c9fb4ce0ab`. `HEAD` and `origin/main` match.
  All 25 files under `crates/refineid-lib-core/src/rapp/`, the crate manifests,
  lockfile, library export, and formal state-machine data are tracked and
  pushed.
- Apple repository: `~/src/ReFineID-Apple`. The RAPP baseline this
  handoff described was `ca3fab2`; the current revision is in the
  status section above. Since 2026-08-21 the remote card is
  compile-gated out of the shipping configurations
  (`REFINEID_REMOTE_CARD`, on in Debug and Profile), so RAPP work
  builds and tests exactly as before in the development
  configurations, and a store artifact carries none of it until the
  qualification matrix in the plan below passes.
- The protocol engine is Swift, in `CardCore/Sources/RappEngine`. There is no
  compiled artifact to pin. Its authority is the vendored specification, the
  formal state model, and the conformance corpus and vectors beside them, and
  its tests fail when the engine and those documents disagree.

### Implemented and verified

- RAPP pairing, authenticated operation transport, explicit phone-holder
  authorization, browser authentication, document signing, acknowledgements,
  durable peer selection/revocation, and immediate durable revocation after one
  authenticated protocol violation are implemented in the Swift engine.
  Activation and PIN management are deliberately not remote RAPP operations.
- macOS ships separate direct-reader and RAPP CryptoTokenKit extensions. The
  reader extension has smart-card access and no network entitlement; the RAPP
  extension has local-network client/server access and no smart-card
  entitlement.
- `cargo test -p refineid-lib-core` passed at the pinned Rust revision.
- The full non-UI Apple suite passed 518 tests in 84 suites, including paired
  browser authentication, document signing, denial, terminal paths, and
  credential-rejection revocation.
- The Swift release manager produced and inspected local iOS and macOS
  production candidates `26.8.17 (60)`. Both passed architecture, signing,
  entitlement, extension-topology, privacy, logging, coverage, quarantine, and
  export gates. These were qualification artifacts, not uploaded releases.

### Not yet proved

- The exact pushed baseline has not completed the recorded physical two-device
  matrix: QR pairing, card status, Safari authentication, document signing,
  denial, card removal, one synthetic authenticated fail-stop violation,
  durable revocation, and manual re-pairing.
- 2026-08-17 integration evidence (not qualification): the iPad
  requester role now exists, and an iPad Simulator completed QR
  pairing, a holder-authorized identity read, persistent-token
  publication, and a Safari suomi.fi login through the physical
  iPhone's NFC card. See the handoff's verified-evidence section.
- The connected development iPhone was locked during the last run. Launching
  the freshly installed Debug app failed for that reason. A macOS “Enable UI
  Automation” dialog may also require the owner to approve Touch ID. Never try
  to bypass either protection.
- A hardware-free RAPP UI qualification harness is still missing. It must run
  the real Rust pairing and authorization coordinators and may virtualize only
  transport and card effects. Do not satisfy this by injecting a fake visible
  SwiftUI state.
- Independent implementation/interoperability and external security review are
  still missing.

### Exact next work

1. Confirm both repositories are clean and still at the revisions above.
2. If the owner has unlocked the development iPhone and approved UI automation,
   run the physical matrix in section 0 and record sanitized evidence against
   both exact commits. Do not intentionally consume a real CAN, PIN 1, PIN 2,
   activation, or PUK retry.
3. Otherwise continue the hardware-free UI harness. Start at
   `Sources/App/RappPairingUI.swift`, `RappAuthorizationInbox.swift`,
   `RappPhoneProxyDispatcher.swift`, `PhonePersistentTokenRelay.swift`, and the
   existing Virtual ID Card/UI-test launch environment. Preserve the real Rust
   protocol path; inject below the semantic dispatcher/card boundary.
4. Add bounded iOS UI-test shards for pairing review, approve/deny, PIN 2
   authorization, one-violation fail-stop, revocation/re-pairing, VoiceOver
   labels, Dynamic Type, and Finnish/Swedish/English strings. Keep each shard
   below the device UI-test timeout.
5. Commit and push each coherent increment. Update the handoff and this status
   block whenever the pinned Rust ABI revision or verified evidence changes.

### RAPP completion project plan

Execute these phases in order. A later phase may start early only when it does
not weaken, bypass, or duplicate the production protocol path established by an
earlier phase.

#### Phase A: preserve a reproducible protocol baseline

Outcome: every shipped Apple artifact is auditable back to pushed Rust source.

- Confirm the pinned Rust and Apple revisions above are reachable from their
  remotes and both worktrees are clean before making changes.
- Change the specification and the formal model first, regenerate the corpus
  and the vectors, re-vendor them, and then make the engine follow.
- If Rust ABI or wire behavior changes, first commit and push Rust, rebuild the
  Apple artifact, then update its pinned Rust hash and handoff in the same Apple
  commit series.
- Keep the Rust conformance corpus and formal state-machine data authoritative.
  Swift tests must consume that corpus rather than restating protocol rules.

Acceptance criteria:

- A clean checkout builds the engine from source with no toolchain beyond
  Xcode.
- The release manager rejects a framework whose recorded source revision,
  slices, symbols, or extension topology does not match the candidate.
- Rust and Apple non-UI RAPP suites pass before UI harness work begins.

#### Phase B: create the hardware-free RAPP system-test seam

Outcome: tests can drive the complete authenticated protocol without a camera,
local network, NFC antenna, or mutable physical card.

- Introduce narrow dependency seams for peer transport and card effects. The
  production defaults remain `PersistentRelaySession` and the NFC/card
  executor; test implementations are compiled or enabled only for Debug/UI
  testing.
- Build an in-memory duplex transport that connects two real
  `RappPairingCoordinator`/`RappConnectionCoordinator` peers and carries the
  exact Rust-generated frames. It may schedule disconnects, duplication,
  reordering, corruption, and expiry, but must not synthesize semantic success.
- Adapt the existing Virtual ID Card as the card-effects implementation. It
  owns card generation, activation state, identity, certificates, CAN, PINs,
  retry counters, card presence, and deterministic injected failures. The
  dispatcher must consume its outcomes through the same result types as NFC.
- Use injectable monotonic time and deterministic test entropy only at the
  protocol test boundary. Production continues using the operating system's
  secure entropy and clock.
- Ensure a test cannot accidentally reach a real reader, NFC session, Keychain
  pairing, or credential store unless that specific integration test opts in.

Acceptance criteria:

- One test process can pair two real protocol peers, persist/select the pair,
  establish a session, request an operation, ask the real authorization inbox,
  execute one virtual card effect, acknowledge it, and close normally.
- Wire/frame mutation reaches the real parser and produces the production
  fail-stop/revocation behavior.
- No test-only branch directly assigns a paired, approved, completed, failed,
  or revoked SwiftUI state.

#### Phase C: expose a Debug-only, accessible UI-test driver

Outcome: XCUITest and a human in Virtual ID Card demonstration mode can drive
the same RAPP behavior.

- Add documented launch arguments/environment for an isolated RAPP test vault,
  in-memory peer transport, deterministic peer fixture, and selected Virtual
  ID Card scenario. Reject these controls in non-Debug builds.
- Let UI tests initiate pairing through the visible pairing controls. QR camera
  input may be replaced by a test scanner source, but the scanned URI must be a
  genuine offer emitted by the other real coordinator.
- Keep the floating Virtual ID Card editor localized in Finnish, Swedish, and
  English. Every value, connection mode, failure injection, and card state must
  have stable accessibility labels, values, hints, traits, and identifiers.
- Make authorization sheets fully operable with VoiceOver, Switch Control,
  keyboard focus, Dynamic Type, increased contrast, and reduced motion. Never
  expose CAN, PIN 1, PIN 2, PUK, digests, keys, or raw frames in accessibility
  text.
- Split UI tests by scenario family so no shard approaches the physical-device
  UI-test timeout. Each test starts with an isolated vault and deterministic
  card state.

Acceptance criteria:

- A human can configure the Virtual ID Card, pair, approve or deny requests,
  inspect revocation, and re-pair using only VoiceOver.
- The release manager proves the driver, floating card, launch controls, test
  credentials, and diagnostics are absent from App Store archives.

#### Phase D: complete the deterministic RAPP behavior matrix

Outcome: all formal states and terminal transitions have application-level
evidence, not only unit-level evidence.

Pairing shards:

- Valid offer, explicit two-sided review, approval, persistence, selection, and
  reconnect.
- Denial, cancel, malformed offer, expired offer, unsupported profile, peer
  mismatch, transport loss at each pairing phase, and requester offer restore.
- Pair removal from each device, durable revocation, and manual re-pairing with
  new keys.

Operation shards:

- Card status and identity read with explicit approval and denial.
- Browser authentication with one approval, one card command, one result, and
  one acknowledgement.
- Document signing with PIN 2 entered only on the phone, cleared after every
  outcome, exactly one card command, and exactly one acknowledgement.
- Busy/concurrent request handling, user cancellation, request expiry, card
  removal before transmit, completion ambiguity, and safe reconnect behavior.

Fail-stop shards:

- Invalid CAN, PIN 1, or PIN 2, authenticated frame corruption, replay,
  sequence violation, peer identity mismatch, impossible transition, and
  unsupported credential request each terminate the current operation as the
  protocol specifies.
- Every authenticated protocol violation immediately and durably revokes the
  pairing on the first incident. There is no warning strike, retry, automatic
  repair, or silent re-pair.
- Credential rejection clears the corresponding local credential state,
  closes the relay/extension operation, and requires explicit user recovery.
- Activation and PIN management requests are rejected because RAPP 0.1 never
  proxies those operations.

Acceptance criteria:

- Every formal transition has at least one positive test and every forbidden
  transition has a rejection/fail-stop test.
- Physical-card-command counters prove zero, one, or the specified exact count
  for every terminal path. Retry-floor refusal always proves zero credential
  transmissions.
- Tests assert durable state after process restart, not merely the final
  in-memory event.

#### Phase E: qualify the exact build on physical Apple hardware

Outcome: the same candidate proven in automation works across real Apple
frameworks, radios, extensions, Safari, NFC, and smart-card hardware.

- Record Apple and Rust commit hashes, version/build, archive identifiers,
  macOS/iOS versions, device models, card generation, reader model, and
  sanitized start state before testing.
- Pair the Mac and iPhone through the visible QR flow; confirm both sides show
  the same reviewed peer and granted profiles.
- Prove status/identity, Safari authentication, document signing, explicit
  denial, card removal before transmit, relay loss, application restart,
  extension restart, peer removal, one synthetic non-credential fail-stop
  violation, durable revocation, and manual re-pairing.
- Exercise the direct-reader and RAPP CryptoTokenKit extensions separately and
  confirm they never claim each other's token class or entitlement capability.
- Capture only sanitized evidence. Do not intentionally submit a wrong real
  CAN, PIN 1, PIN 2, activation PIN, or PUK, and never test a final retry.

Acceptance criteria:

- The exact archived candidate passes the complete recorded physical matrix.
- No result depends on a development-only entitlement, retained pairing,
  retained credential, debugger attachment, or manually launched extension.

#### Phase F: independent interoperability and security review

Outcome: RAPP is demonstrably a portable protocol rather than an Apple-only
implementation detail.

- Implement one minimal independent requester or authorizer from the published
  protocol and conformance corpus without importing the shared Rust library.
- Cross-run positive, negative, expiry, replay, transcript-binding, revocation,
  and fail-stop vectors against the Apple implementation.
- Obtain external review of cryptography, key lifecycle, pairing ceremony,
  QR/bootstrap authenticity, transcript binding, sequence/replay protection,
  privacy metadata, denial of service, local-network exposure, and extension
  teardown behavior.
- Resolve every high-severity finding before TestFlight; record accepted lower
  risks with owner, rationale, and an explicit review date.

Acceptance criteria:

- The independent implementation interoperates without Apple-private behavior
  or undocumented assumptions.
- Protocol and threat-model documents match the code and conformance corpus.

#### Phase G: freeze and distribute the release candidate

Outcome: TestFlight/App Store receives exactly the candidate that passed all
required gates.

- Run full Rust, Swift, UI, accessibility, archive, privacy, localization, and
  physical-hardware gates through the Swift release manager.
- Generate TestFlight “What to Test” notes from the exact diff and include the
  pairing, approval, revocation, and Virtual ID Card reviewer walkthrough.
- Upload only after a human reviews the notes and recorded evidence. Never
  rebuild between qualification and upload.
- Record build identifiers, source revisions, generated-artifact provenance,
  tester groups, review notes, and rollback decision in the release evidence.

Acceptance criteria:

- Uploaded binaries hash-identically match the qualified exports.
- App Store archives contain no Debug harness, diagnostics, logs, credential
  traces, test credentials, or Virtual ID Card implementation not intended for
  review/demo distribution.

## 0. Release blockers

Audited against source 2026-08-16; rescoped 2026-08-21 for the iPhone
MVP (Documentation/decisions.md, 2026-08-21): the remote card and
activation are compile-gated out of the shipping configurations, so
their qualification no longer blocks this release - it blocks turning
them back on. The waiting macOS 26.8.16 (114) submission was withdrawn
in App Store Connect on 2026-08-21; until the macOS release decides its
shape, a macOS candidate cut from this source deliberately fails
archive inspection, because the inspector still describes the RAPP-on
macOS topology while the shipping configurations gate the remote card
off. Each item states only what remains; the resolved halves of the
original wording are recorded in git history.

- [ ] Make the non-UI suite green again:
  `RappIntegrationTests/credentialRejectionRevokesBothPeersWithoutAnotherExecution`
  fails on main (verified also at 2cd5248, before the gating work - six
  vault-revocation expectations after a rejected credential). RAPP is
  gated out of the release, but the release pipeline runs the whole
  suite in Debug, where RAPP is on.
- [ ] Cut the gated iPhone candidate and push the reshaped metadata:
  `Metadata/appstore.json` now carries the activation-free reviewer
  walkthrough, no RAPP paragraph, and iPhone-only descriptions in three
  languages; they reach App Store Connect through the release manager's
  metadata commands at submission time.
- [ ] Finish serial-binding the contactless prime store. The published
  CryptoTokenKit identity, registration, and revocation are already
  printed-serial-derived and every mint refuses a serial-less prime; still
  open: primes are keyed by the batch-wide ATR digest, so one prime exists
  per card family and a second same-generation card silently supersedes the
  first, `PrimedIdentity.tokenSerial` remains optional in the type, and no
  test covers the wrong-card-same-ATR path.
- [ ] Close the remaining credential-clearing boundaries. Card-error
  revocation, extension restart, and card and reader removal are handled;
  still open: no sleep, screen-lock, or logout handler exists, the PIN 2
  window can survive a card error or removal for its full 60 seconds,
  `CardCredentialStore` writes `AfterFirstUnlockThisDeviceOnly` while its
  header claims `WhenUnlockedThisDeviceOnly`, and the macOS offered-CAN file
  outlives a crash, sleep, or lock.
- [ ] Make the retry floor provable. `RetryFloor` is wired into every
  reader-path credential operation; still open: the NFC deadline path
  transmits PIN 1 with no immediately preceding probe (documented, but this
  wording and that exception must agree), zero attempts proceeds and
  transmits instead of refusing as blocked (`refuseBlocked` is unreachable),
  enforcement is caller convention rather than type, and no test proves zero
  credential commands on a production floor refusal. Never deliberately
  exercise a real card's final attempt.
- [ ] Re-prove the clean-device suomi.fi login and demonstration-mode
  onboarding on the exact App-Store-shaped candidate - now the gated
  iPhone shape: floor 26, iPhone-only, no remote card, no activation;
  the clean-VM proof and the shipped demonstration mode are recorded in
  decisions.md and history.
- [ ] Film, sanitize, host, and link the App Review demonstration video,
  then answer the Resolution Center message. App Review asked for it
  under guideline 2.1 on 2026-08-16 after reviewing on an iPad Air,
  which has no NFC antenna; the shot list, sanitization rules, notes
  text, and reply are in `Documentation/app-review-demo-video.md`. Film
  the gated candidate, whose demonstration card arrives already
  activated, so the video and the reviewed build tell one story. The
  nfc required capability also keeps future reviews off iPads.

The RAPP physical two-device qualification matrix (pairing, status,
Safari authentication, document signing, denial, card removal, one
authenticated fail-stop teardown, manual re-pairing, against exact
commits, without spending a real credential retry) moved out of this
release's blockers when the remote card was gated off. It is the
acceptance gate for turning `REFINEID_REMOTE_CARD` back on and for the
macOS release, and it stands unchanged in the RAPP plan above.

## 1. Product and public documentation

- [ ] Publish one supported-hardware table covering card generations, key
  profiles, USB readers, iPhone NFC, and declared system consumers.
- [ ] Reconcile public documentation with the implemented PIN 1 cache and retry
  policy.
- [ ] Keep Finnish, Swedish, and English terminology consistent. Visible UI
  strings already use spaced `PIN 1` and `PIN 2` throughout; the internal
  documentation largely does not.

## 2. Repository controls

- [ ] Protect `main` and release tags against force pushes, deletion, and
  unreviewed release creation; require the relevant passing checks.
- [ ] Enable secret scanning, push protection, bounded dependency updates, and
  dependency review where GitHub provides them.
- [ ] Restrict GitHub Apps, Actions, Xcode Cloud, deploy keys, webhooks, and
  environment secrets to the minimum required access.
- [ ] Add issue and pull-request guidance prohibiting PINs, PUKs, certificate
  dumps, full serials, and unsanitized traces.
- [ ] Complete a license, provenance, secret, and PII audit of reachable source,
  fixtures, commits, and release tags.

## 3. Deterministic safety verification

- [ ] Add instrumented test transports around every credential path and prove
  exact card-command counts for success, rejection, transport ambiguity, and
  retry refusal.
- [ ] Cover retry states unknown, malformed, zero, one, two, three, four, and
  pristine, including the wrong-at-three transition to two with no later
  credential transmission.
- [ ] Cover removal, reinsertion, fast card swap, reader contention, and
  concurrent credential requests at every credential boundary.
- [ ] Finish the Virtual ID Card XCUITest harness so the formal state machine,
  its GUI editor, VoiceOver, localization, reader/NFC transports, and injected
  failures are driven through the same application paths as real cards.
- [ ] Keep all release tests deterministic and independent of sleeps, developer
  home directories, credentials, physical-card mutation, and retained logs.
- [ ] Prove TestFlight and App Store archives contain no diagnostics, logging,
  credential APDUs, secrets, personal data, or debug-only UI.
- [ ] Run keyboard, VoiceOver, Dynamic Type, increased-contrast, reduced-motion,
  focus-order, error-announcement, and Accessibility Inspector coverage for
  every shipping state.

## 4. Exact-build hardware evidence

- [ ] Maintain a versioned operator procedure and sanitized evidence record for
  each supported card generation, reader, transport, and platform.
- [ ] Verify activation, partial activation recovery, authentication, document
  signing and validation, PIN changes, PUK resets, and retry refusal against
  the exact candidate build.
- [ ] Verify iPhone pairing, iPhone-backed Safari authentication, peer removal,
  relay rejection, reconnection, and rejection of an unpaired requester.
- [ ] Verify reader/card removal, reinsertion, swap, contention, sleep, wake,
  extension restart, application restart, and system restart.
- [ ] Retain only sanitized results tied to source commit, version, build,
  archive inspection, hardware, and approver.

## 5. TestFlight

- [ ] Add repository-owned, platform-specific TestFlight `What to Test` notes.
  The Swift release manager may generate their draft from commits since the
  previous tag and apply them only to the exact uploaded build.
- [ ] Create or confirm named internal iOS and macOS tester groups and distribute
  the exact approved development build to them.
- [ ] Exercise clean installation, upgrade, downgrade refusal, uninstall, and
  extension disappearance using the TestFlight artifacts.
- [ ] Prepare external tester groups, Beta App Review information, a synthetic
  Virtual ID Card walkthrough, and credential-free hardware video.
- [ ] Cut `beta` builds only after internal evidence passes, and `rc` builds only
  after external, hardware, accessibility, privacy, and metadata gates pass.
- [ ] Freeze the exact tested release-candidate build selected for App Review.

## 6. App Store release

- [ ] Complete and review localized name, subtitle, description, keywords,
  screenshots, privacy information, age rating, pricing, availability, export
  compliance, accessibility declarations, review contact, and EU trader data.
- [ ] Give App Review accurate card/reader instructions, Virtual ID Card steps,
  hardware limitations, extension behavior, relay behavior, and a sanitized
  demonstration video.
- [ ] Generate localized App Store `What's New` drafts from the exact release
  diff, and require explicit human approval before applying them.
- [ ] Attach only the exact TestFlight-tested candidate, submit it through the
  Swift release manager, and retain the submission identifier and review state.
- [ ] After approval, create final platform release tags at the candidate source
  commit and release manually with the recorded owner approval.
- [ ] Publish support and known-limitations information and define pause,
  rollback, emergency-update, and post-release monitoring responsibilities.

## 7. Xcode Cloud

- [ ] Connect Xcode Cloud with minimum repository access and a deterministic
  verification workflow using the committed shared scheme.
- [ ] Add tag-driven internal, beta, and release-candidate workflows for iOS and
  macOS without automatic distribution on every source change.
- [ ] Retain build, test, analysis, archive-inspection, and release-candidate
  evidence beyond Xcode Cloud's artifact-retention window.

## 8. RAPP

- [ ] Prototype interoperable non-Apple requesters and authorizers against the
  current Apple implementation after the Apple release baseline is frozen.
