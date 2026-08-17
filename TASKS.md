# Apple release task list

Last reviewed: 2026-08-17

Completed work is removed. This file contains only concrete outcomes that are
still required for an Apple beta, App Store release, or the next protocol
milestone.

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
- Apple repository: `~/src/ReFineID-Apple` at
  `ca3fab2fb9daeeed179d36816c1c55ed91131d28`. `HEAD` and `origin/main` match.
  The checked-in `ReFineIDRappFFI.xcframework` and generated Swift bindings are
  explicitly pinned in the handoff to the Rust revision above.
- Do not replace the checked-in framework without rebuilding it from a pushed
  Rust revision and updating the pinned revision in the same commit series.

### Implemented and verified

- RAPP pairing, authenticated operation transport, explicit phone-holder
  authorization, browser authentication, document signing, acknowledgements,
  durable peer selection/revocation, and immediate durable revocation after one
  authenticated protocol violation are implemented through the shared Rust
  core. Activation and PIN management are deliberately not remote RAPP
  operations.
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

## 0. Release blockers

Audited against source 2026-08-16. Each item states only what remains;
the resolved halves of the original wording are recorded in git history.

- [ ] Qualify the committed RAPP candidate on physical macOS and iPhone
  hardware. Record clean pairing, status, Safari authentication, document
  signing, user denial, card removal, one authenticated fail-stop teardown,
  and manual re-pairing against exact commits. Do not spend a real credential
  retry. The protocol, explicit pairing, per-operation authorization, durable
  one-violation revocation, and separate direct-reader and persistent-token
  extension topology are implemented; this item is release evidence, not a
  design placeholder.
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
  onboarding on the exact App-Store-shaped candidate; the clean-VM proof and
  the shipped demonstration mode are recorded in decisions.md and history.
- [ ] Film, sanitize, host, and link the App Review demonstration video for
  iOS 26.8.16 (114), then answer the Resolution Center message. App Review
  asked for it under guideline 2.1 on 2026-08-16 after reviewing on an iPad
  Air, which has no NFC antenna; the shot list, sanitization rules, notes
  text, and reply are in `Documentation/app-review-demo-video.md`.

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
