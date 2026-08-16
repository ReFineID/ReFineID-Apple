# Apple release task list

Last reviewed: 2026-08-16

Completed work is removed. This file contains only concrete outcomes that are
still required for an Apple beta, App Store release, or the next protocol
milestone.

## 0. Release blockers

Audited against source 2026-08-16. Each item states only what remains;
the resolved halves of the original wording are recorded in git history.

- [ ] Give the iPhone relay explicit cryptographic pairing before it ships.
  The relay is compile-gated off by FEATURE_IPHONE_RELAY since 2026-08-16:
  `PersistentCardRelay` accepts every invitation on `refineid-rly`, persists
  no remote peer identity, and the phone serves identity and signature
  requests from the keychain PIN 1 without per-request consent. Re-enabling
  needs a pairing exchange, a persisted peer allowlist checked on both
  sides, per-request phone consent, accept/reject tests, restored network
  entitlements and Bonjour declarations, and a decided macOS driver shape:
  the relay build replaced the smart-card driver in the macOS extension
  plist, so as built one macOS binary cannot serve a reader and the relay
  at once.
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

- [ ] Specify Remote Authorization Proxy Protocol roles, typed operations,
  credential profiles, transport profiles, threat model, and privacy model.
- [ ] Design cross-platform high-entropy pairing, end-to-end authenticated
  sessions, replay protection, request expiry, explicit phone consent, and an
  untrusted Internet rendezvous relay.
- [ ] Define the protocol and application state machines in machine-readable
  form and verify implementation transitions against them.
- [ ] Prototype interoperable Apple and non-Apple requesters and authorizers only
  after the current Apple release baseline is frozen.
