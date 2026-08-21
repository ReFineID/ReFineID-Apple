# Apple release task list

Last reviewed: 2026-08-21. Completed work is removed; this file holds only
outcomes still required for a beta, an App Store release, or the next
protocol milestone.

## Status 2026-08-21

- First release: iPhone MVP on iOS 26 (decisions.md 2026-08-21). Implemented
  and pushed; `main` and `origin/main` at `f8f00e6`.
- Ships: one-step NFC priming, Safari login, document signing and checking,
  PIN changes, USB-C reader signing, demo mode (virtual card starts activated).
- Gated out of TestFlight/Release: remote card (`REFINEID_REMOTE_CARD`) and
  activation (`FEATURE_CARD_ACTIVATION`; unactivated cards see a localized
  refusal). Shipping configs: floor 26, iPhone-only, `nfc` required
  capability, `Config/ReFineID-iOS-Store-Info.plist` (no Bonjour or
  local-network keys). Debug/Profile: floor 16, both families, gates on.
  Enforced by the archive inspector and `RappShippingConfigurationTests`.
- Verified 2026-08-21: iOS TestFlight, iOS Debug, and macOS TestFlight build
  clean; store bundle carries reader + discovery extensions only,
  MinimumOSVersion 26.0, UIDeviceFamily [1]; non-UI suite 528/529 (the one
  failure is blocker 1).
- App Store Connect: iOS 26.8.16 (114) awaits the guideline 2.1 demo video;
  macOS submission withdrawn 2026-08-21. A macOS candidate deliberately fails
  archive inspection until the macOS release decides its shape.

## 0. Release blockers

- [ ] Green the non-UI suite:
  `RappIntegrationTests/credentialRejectionRevokesBothPeersWithoutAnotherExecution`
  fails on main (also at `2cd5248`, pre-gating). The pipeline runs the suite
  in Debug, where RAPP is on.
- [ ] Cut the gated iPhone candidate; push the reshaped `Metadata/appstore.json`
  (activation-free walkthrough, no RAPP paragraph, iPhone-only descriptions)
  at submission.

The RAPP physical qualification matrix is not a blocker here; it gates
re-enabling `REFINEID_REMOTE_CARD` and the macOS release (Phase E below).

## 1. Product and public documentation

- [ ] Publish one supported-hardware table: card generations, key profiles,
  USB readers, iPhone NFC, declared system consumers.
- [ ] Reconcile public documentation with the implemented PIN 1 cache and
  retry policy.
- [ ] Keep fi/sv/en terminology consistent; UI already uses spaced `PIN 1` /
  `PIN 2`, internal documentation largely does not.

## 2. Repository controls

- [ ] Protect `main` and release tags: no force push, deletion, or unreviewed
  release; require passing checks.
- [ ] Enable secret scanning, push protection, bounded dependency updates,
  dependency review.
- [ ] Restrict GitHub Apps, Actions, Xcode Cloud, deploy keys, webhooks, and
  secrets to minimum access.
- [ ] Add issue/PR guidance prohibiting PINs, PUKs, certificate dumps, full
  serials, unsanitized traces.
- [ ] Audit reachable source, fixtures, commits, and tags for license,
  provenance, secrets, PII.

## 3. Deterministic safety verification

The first three were release blockers until descoped from the MVP on
2026-08-21; each hardens behavior that already fails safe. Kept so the
findings survive.

- [ ] Serial-bind the contactless prime store: primes are keyed by the
  batch-wide ATR digest, so a second same-generation card silently supersedes
  the first; `PrimedIdentity.tokenSerial` is still optional; no test covers
  wrong-card-same-ATR.
- [ ] Close credential-clearing boundaries: no sleep/lock/logout handler; the
  PIN 2 window can survive a card error for its full 60 s;
  `CardCredentialStore` writes `AfterFirstUnlockThisDeviceOnly` while its
  header claims `WhenUnlockedThisDeviceOnly`; the macOS offered-CAN file
  outlives a crash, sleep, or lock.
- [ ] Make the retry floor provable: the NFC deadline path transmits PIN 1
  without an immediately preceding probe (doc and exception must agree); zero
  attempts transmits instead of refusing (`refuseBlocked` unreachable);
  enforcement is convention, not type; no test proves zero credential
  commands on a floor refusal. Never exercise a real card's final attempt.
- [ ] Instrument test transports on every credential path; prove exact
  card-command counts for success, rejection, ambiguity, retry refusal.
- [ ] Cover retry states unknown, malformed, 0–4, pristine, including
  wrong-at-three → two with no later transmission.
- [ ] Cover removal, reinsertion, fast swap, reader contention, concurrent
  requests at every credential boundary.
- [ ] Finish the Virtual ID Card XCUITest harness: state machine, editor,
  VoiceOver, localization, transports, injected failures through the same
  paths as real cards.
- [ ] Keep release tests deterministic: no sleeps, developer homes,
  credentials, physical-card mutation, retained logs.
- [ ] Prove store archives contain no diagnostics, logging, credential APDUs,
  secrets, personal data, or debug-only UI.
- [ ] Run keyboard, VoiceOver, Dynamic Type, contrast, reduced-motion,
  focus-order, error-announcement, and Accessibility Inspector coverage for
  every shipping state.

## 4. Exact-build hardware evidence

- [ ] Maintain a versioned operator procedure and sanitized evidence record
  per card generation, reader, transport, platform.
- [ ] Verify activation, partial-activation recovery, authentication, signing
  and validation, PIN changes, PUK resets, retry refusal against the exact
  candidate.
- [ ] Verify iPhone pairing, iPhone-backed Safari auth, peer removal, relay
  rejection, reconnection, unpaired-requester rejection.
- [ ] Verify reader/card removal, reinsertion, swap, contention, sleep, wake,
  extension/app/system restart.
- [ ] Retain only sanitized results tied to commit, version, build, archive
  inspection, hardware, approver.

## 5. TestFlight

- [ ] Repository-owned, platform-specific `What to Test` notes; drafts may be
  generated from commits, applied only to the exact uploaded build.
- [ ] Named internal tester groups; distribute the exact approved build.
- [ ] Exercise clean install, upgrade, downgrade refusal, uninstall,
  extension disappearance from TestFlight artifacts.
- [ ] Prepare external groups, Beta App Review info, Virtual ID Card
  walkthrough, credential-free hardware video.
- [ ] `beta` builds only after internal evidence; `rc` only after external,
  hardware, accessibility, privacy, metadata gates.
- [ ] Freeze the exact tested candidate selected for App Review.

## 6. App Store release

- [ ] Complete localized name, subtitle, description, keywords, screenshots,
  privacy, age rating, pricing, availability, export compliance,
  accessibility declarations, review contact, EU trader data.
- [ ] Give App Review accurate card/reader instructions, Virtual ID Card
  steps, hardware limitations, extension behavior, and the video.
- [ ] Localized `What's New` drafts from the exact diff, human-approved.
- [ ] Attach only the exact tested candidate; submit through the release
  manager; retain submission identifier and state.
- [ ] After approval: final platform tags at the candidate commit; manual
  release with recorded owner approval.
- [ ] Publish support and known limitations; define pause, rollback,
  emergency-update, and monitoring responsibilities.

## 7. Xcode Cloud

- [ ] Connect with minimum access and a deterministic verification workflow
  on the committed shared scheme.
- [ ] Tag-driven internal, beta, and rc workflows; no automatic distribution
  per source change.
- [ ] Retain build, test, analysis, inspection, and rc evidence beyond Xcode
  Cloud's retention window.

## 8. RAPP

- [ ] Prototype interoperable non-Apple requesters and authorizers after the
  Apple release baseline is frozen.

## RAPP handoff

Read `Documentation/rapp-implementation-handoff.md` before changing RAPP.

Baseline: Rust `~/src/ReFineID` at
`c745bb0cbab18b82877ddfa1143690c9fb4ce0ab`, pushed. Apple revision: status
above; RAPP is compile-gated out of shipping configs since 2026-08-21,
unchanged in Debug/Profile. Engine: Swift, `CardCore/Sources/RappEngine`;
its authority is the vendored spec, formal state model, and conformance
corpus, and its tests fail on disagreement.

Done: pairing, authenticated transport, explicit phone-holder authorization,
browser auth, document signing, acknowledgements, durable
selection/revocation, one-violation durable fail-stop. macOS ships separate
reader and RAPP CTK extensions (smart-card vs network entitlements, never
both). `cargo test -p refineid-lib-core` green at the pinned revision.
Activation and PIN management are deliberately not RAPP operations.

Not proved: the physical two-device matrix (Phase E); a hardware-free RAPP UI
harness — it must run the real Rust coordinators and may virtualize only
transport and card effects, never inject SwiftUI state; independent interop
and external security review. The 2026-08-17 iPad-requester run is evidence.

Next: blocker 1; then the hardware-free harness (start at `RappPairingUI`,
`RappAuthorizationInbox`, `RappPhoneProxyDispatcher`,
`PhonePersistentTokenRelay`; inject below the dispatcher/card boundary); then
bounded UI-test shards (pairing, approve/deny, PIN 2, fail-stop,
revocation/re-pair, VoiceOver, Dynamic Type, fi/sv/en). Push each coherent
increment; update the handoff when the pinned Rust revision or evidence
changes.

### RAPP plan

Phases in order; a later phase may start early only if it does not weaken or
bypass the production protocol path.

- A, reproducible baseline: change spec and formal model first, regenerate
  and re-vendor corpus/vectors, then the engine; push Rust before the Apple
  commit that pins it. Accept: clean checkout builds with Xcode alone; the
  release manager rejects mismatched provenance; both RAPP suites green.
- B, hardware-free seam: narrow seams for peer transport and card effects,
  production defaults unchanged; an in-memory duplex transport between two
  real coordinators carrying real frames (may drop, duplicate, reorder,
  corrupt, expire; never synthesizes success); Virtual ID Card as the card
  effects; injectable time/entropy at the test boundary only; tests reach no
  real reader, NFC, Keychain, or credential store without opt-in. Accept: one
  process runs pair→session→operation→authorize→execute→acknowledge with real
  peers; frame mutation produces production fail-stop; no test branch assigns
  UI state.
- C, Debug-only UI driver: launch controls for isolated vault, in-memory
  transport, fixtures, scenarios, rejected outside Debug; pairing driven
  through the visible controls (scanner replaceable, the URI must be a real
  offer); editor and sheets localized fi/sv/en and fully accessible; no
  secrets in accessibility text; shards below the device timeout. Accept:
  VoiceOver-only walkthrough works; the release manager proves the driver
  absent from store archives.
- D, behavior matrix: pairing (offer, review, approval, persistence,
  reconnect; denial, malformed/expired offer, transport loss per phase,
  removal, durable revocation, re-pair with new keys); operations (status,
  browser auth, signing with PIN 2 on the phone only, busy, cancel, expiry,
  card removal, completion ambiguity, safe reconnect); fail-stop (bad
  credentials, corruption, replay, sequence violation, identity mismatch —
  first authenticated violation durably revokes, no retry or silent re-pair;
  credential rejection clears local state; activation/PIN management always
  rejected). Accept: every formal transition tested both ways; exact
  card-command counts proven, retry-floor refusal proves zero; durable state
  asserted after restart.
- E, physical qualification: record hashes, versions, devices, card, reader,
  sanitized start state; QR pairing, status, Safari auth, signing, denial,
  card removal, relay loss, app/extension restart, one synthetic fail-stop,
  durable revocation, re-pairing; extensions never claim each other's
  capability; never spend a real credential retry. Accept: the exact archived
  candidate passes the whole recorded matrix without dev-only crutches.
- F, independent interop and review: a minimal independent peer from the
  published spec and corpus (no shared Rust); cross-run the vectors; external
  review of crypto, pairing ceremony, transcript binding, replay, privacy,
  DoS, local-network exposure, teardown; high-severity findings resolved
  before TestFlight, accepted risks recorded with owner and date. Accept:
  interop without Apple-private assumptions; docs match code and corpus.
- G, freeze and distribute: all gates through the release manager; notes from
  the exact diff, human-reviewed before upload; never rebuild between
  qualification and upload; record identifiers, provenance, tester groups,
  rollback decision. Accept: uploads hash-match the qualified exports;
  archives carry no debug harness.
