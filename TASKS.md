# Apple release task list

Last reviewed: 2026-08-16

Completed work is removed. This file contains only concrete outcomes that are
still required for an Apple beta, App Store release, or the next protocol
milestone.

## 0. Release blockers

- [ ] Bind every stored contactless prime to a card-unique serial after PACE;
  never use the batch-wide ATR digest as the lasting card identity.
- [ ] Clear credential state on every ambiguous completion and relevant
  lifecycle boundary: card or reader removal, replacement, contention, sleep,
  screen lock, logout, extension restart, transport failure, and card error.
- [ ] Prove immediately before every PIN-bearing operation that zero attempts
  means blocked, one or two means refusal, and three or more permits at most one
  card attempt. Never deliberately exercise a real card's final attempt.
- [ ] Replace the current nearby iPhone relay's unauthenticated peer trust with
  explicit cryptographic pairing before external TestFlight or App Store use.
- [ ] Resolve the remaining iOS trust-chain and App Review onboarding decision
  with an App-Store-shaped build.

## 1. Product and public documentation

- [ ] Publish one supported-hardware table covering card generations, key
  profiles, USB readers, iPhone NFC, and declared system consumers.
- [ ] Reconcile public documentation with the implemented PIN 1 cache and retry
  policy.
- [ ] Correct App Store metadata and review notes for the current iOS demo,
  document signing, and iPhone-backed macOS identity. Remove claims that macOS
  has no listener or remote-card path.
- [ ] Keep Finnish, Swedish, and English terminology consistent, including
  visible `PIN 1` and `PIN 2` spelling.

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

- [ ] Add physical-transmit-count spies around every credential path and prove
  exact command counts for success, rejection, transport ambiguity, and retry
  refusal.
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
- [ ] Verify supported Apple Silicon and Intel Macs while both architectures are
  declared.
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
