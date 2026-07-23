# Apple release task list

Last reviewed: 2026-07-23



Legend:

- `[ ]` not complete
- `[!]` blocked; add the blocker and owner immediately below the task
- remove completed



## P0. Release feasibility blockers

- [ ] Confirm ownership of the intended app and extension bundle identifiers on
  the current Apple Developer team; historical projects used multiple teams.
- [ ] Prove the required smart-card APIs work from a sandboxed pure-Swift host and
  CTK extension on a clean supported Mac.
- [ ] Prove a clean-Mac trust-chain solution without `sudo`, a package installer,
  or silent System Keychain modification.
- [ ] Verify whether publishing the complete required issuer chain through CTK is
  sufficient for each promised browser/system authentication flow.
- [ ] If external trust installation remains necessary, document and validate the
  Apple-native user flow and reconsider the one-install App Store promise.
- [ ] Decide EU trader status and review the address, phone, and email that Apple
  will display before enabling EU availability.
- [ ] Do not start an external beta until all P0 decisions have recorded evidence.

## 0. Decisions and repository foundation

  build number, and the matching tag vocabulary (`Documentation/release-plan.md`,
  "Calendar versioning").
- [ ] Add `SECURITY.md` with private reporting instructions and supported
  versions.
- [ ] Add contribution guidance and the source/provenance policy.
- [ ] Record architecture decisions for the pure-Swift CTK core, retry floor,
  cache invariant, and tag-driven distribution.
- [ ] Decide and register the final app and extension bundle identifiers.
  Decided 2026-07-22 (`Documentation/decisions.md`: `fi.refineid.ReFineID` +
  `fi.refineid.ReFineID.ctk`); explicit App ID registration on the release
  team still pending.
- [ ] Decide the initial supported card generations, key profiles, readers, and
  system consumers.
- [ ] Define how versioned public protocol stories and test vectors are imported
  without copying private history or cardholder data.
- [ ] Reconcile the public ReFineID documentation with this plan, including its
  contradictory statements about cached PIN1 use for TLS authentication.

## 1. GitHub controls and public-readiness

- [ ] Set repository Actions permissions to read-only by default.
- [ ] Permit write permissions only in named release workflows that require them.
- [ ] Enable private-repository secret scanning and push protection if available.
- [ ] Add dependency review and automated dependency updates with bounded scope.
- [ ] Add a `main` ruleset requiring pull requests, resolved conversations, no
  force pushes or deletions, and the relevant passing checks.
- [ ] Require signed commits or vigilant mode only after confirming the chosen
  policy works with Xcode Cloud and maintainers.
- [ ] Restrict GitHub App and Xcode Cloud access to the minimum repositories and
  permissions required.
- [ ] Add issue and pull-request templates that prohibit PINs, PUKs, certificate
  dumps, full serials, and unsanitized logs.
- [ ] Run a secret and PII scan across every reachable commit and tag.
- [ ] Audit license and provenance for every imported source file and fixture.
- [ ] Review repository settings, member access, deploy keys, webhooks, and
  environment secrets before public visibility.
- [ ] Flip the repository to public only after the public-source release gate is
  signed off.
- [ ] At the visibility flip, attach the organization's recommended security
  configuration and enable every protection that was unavailable while private.
- [ ] Protect `macos-v*` and `ios-v*` tags from deletion or rewriting and restrict
  release-tag creation to release authority.
- [ ] Restrict third-party Actions to an allowlist and pin every external action
  to a full commit digest.

## 2. Apple account and App Store Connect

- [ ] Confirm the Apple Developer Program membership is active and agreements are
  current for the release account.
- [ ] Decide Individual versus organization membership before creating the first
  App Store record; record the public developer/seller name.
- [ ] If organization publication is selected, complete Apple's membership
  conversion and D-U-N-S requirements before reserving the product record.
- [ ] Complete the EU Digital Services Act trader decision and verify all public
  contact information before selecting EU availability.
- [ ] Add the release Apple Account to Xcode and confirm the correct team.
- [ ] Create or confirm the explicit App ID for ReFineID.
- [ ] Create or confirm the explicit App ID for the CTK extension.
- [ ] Create the macOS app record in App Store Connect.
- [ ] Enable Xcode-managed signing for app and extension targets.
- [ ] Confirm Xcode Cloud can manage development and distribution signing without
  exported private keys in the repository.
- [ ] Record the App Store SKU, bundle identifiers, team identifier, category,
  free pricing, regions, and release owner in a non-secret release record.
- [ ] Configure App Store Connect roles using least privilege.

## 4. Refined Swift card core

- [ ] Prove and implement the clean-machine trust/chain strategy without a
  privileged System Keychain installer (iOS trust onboarding is P0 gate 2).
- [ ] Implement supported RSA and ECC authentication-key profiles explicitly.
  ECC P-384 is implemented and hardware-verified; RSA-3072 is recognized but
  deliberately not yet signable (fail-closed, not published).

- [ ] Implement RSA/ECDSA result normalization and local signature verification.
  ECDSA `r||s`->X9.62 DER (`EcdsaSignature`) with pre-return local verify is done
  and hardware-verified; RSA normalization is not.


## 5. Credential-command safety

- [ ] Add physical-transmit-count spies and tests around every credential path.
  `ScriptedChannel` asserts the exact transmit sequence for the read paths; a
  dedicated spy around the VERIFY path is still to add.
- [ ] Clear all credential state on ambiguous completion (cache clears on wrong
  PIN and card change; exhaustive ambiguous-completion coverage still to prove).

## 6. CTK extension


- [ ] Handle card removal, reinsertion, fast same-reader swap, reader contention,
  extension reuse, and extension termination (cache resets on a fresh token and
  the OS reaps the process; full matrix still to test).

## 7. PIN1 cache

- [ ] Clear on removal, card change, wrong PIN, management notification,
  reconnect, reset, screen lock, logout, sleep, identity uncertainty, transport
  ambiguity, and card error. Done for wrong PIN, card change (serial), fresh
  token (`reset`), and non-pristine (latch); the OS reaps the process between
  flows. The remaining lifecycle notifications still to wire.
- [ ] Prove status reads, prompts, lookups, failures, and contention do not refresh
  or unnecessarily evict an eligible entry.
- [ ] Test timeout boundaries with a fake monotonic clock; do not use sleeps.
  Expiry is tested via an injectable zero window (no sleeps); an exact
  just-under/just-over boundary with a fake clock is still to add.
- [ ] Test concurrent checkout so one cached value cannot be used twice in
  parallel or restored after an uncertain operation (state is `Mutex`-guarded;
  a concurrency test is still to add).

## 8. Native macOS status application

- [ ] Implement a minimal SwiftUI window with native macOS behavior.
- [ ] Show application and bundled extension versions.
- [ ] Research and use only a public API for extension readiness; otherwise use
  precise wording such as "driver included" rather than claiming enablement.
- [ ] Show reader absent, reader available, card inserted, contention, and
  uncertain states.
- [ ] Show supported and unsupported card state without exposing full serials.
- [ ] Show PIN1, PIN2, and PUK attempts remaining from a side-effect-free read.
- [ ] Explain the low-attempt (one or two) CTK refusal and zero-attempt blocked
  state.
- [ ] Link to issuer recovery guidance without pretending v1.0 can unblock.
- [ ] Use manual or event-driven refresh; do not use disruptive periodic polling.
- [ ] Prove opening, closing, and refreshing the app does not reset the card,
  interfere with CTK, or alter cache lifetime.
- [ ] Add useful no-reader, no-card, unsupported-card, and App Review states.
- [ ] Complete keyboard-only and VoiceOver operation.
- [ ] Verify increased contrast, reduced motion, text scaling, focus order, and
  error announcements.
- [ ] Run Accessibility Inspector and automated accessibility audits for every
  status and error state.
- [ ] Complete Accessibility Nutrition Labels using verified behavior only.
- [ ] Add About, license, privacy, support, and security-reporting information.
- [ ] Confirm v1.0 has no portrait, stored handwritten-signature, activation,
  PIN-change, or PUK-unblock UI.

## 9. Automated verification

- [ ] Unit-test every parser with valid and malformed boundary cases.
- [ ] Add provenance-marked, sanitized vectors for every supported card profile.
- [ ] Add aggregate response-size, continuation-count, and timeout limits.
- [ ] Test retry states: unknown, malformed, zero, one, two, three, four, and
  pristine.
- [ ] Test same-card reinsertion and same-reader A-to-B fast swaps.
- [ ] Test removal and contention at every boundary around serial check, retry
  check, PIN verification, and signing.
- [ ] Test wrong-PIN-at-three transitions to two and prevents another CTK
  attempt.
- [ ] Test RSA and ECC signature inputs, output encodings, and local verification.
- [ ] Test logs and diagnostic exports for PIN, PUK, serial, certificate, and APDU
  leakage.
- [ ] Add differential tests whose expectations are independent of both Swift and
  Rust implementations.
- [ ] Add fuzz targets or an equivalent deterministic malformed-input corpus.
- [ ] Run tests under Thread Sanitizer and Address Sanitizer where supported.
- [ ] Run Xcode static analysis with zero release warnings.
- [ ] Make all release tests deterministic and independent of a developer home
  directory.

## 10. Xcode Cloud

- [ ] Connect Xcode Cloud to this GitHub repository with minimum access.
- [ ] Configure the first workflow in Xcode using the committed shared scheme.
- [ ] Disable the suggested every-change distribution behavior.
- [ ] Add an Apple verification workflow for selected pull-request paths.
- [ ] Add `macos-v*-dev.*` internal-TestFlight workflow.
- [ ] Add `macos-v*-beta.*` external-TestFlight workflow.
- [ ] Add `macos-v*-rc.*` App-Store-eligible candidate workflow.
- [ ] Enable auto-cancel for superseded verification builds.
- [ ] Pin supported Xcode and macOS runner versions or managed aliases and record
  intentional upgrades.
- [ ] Keep `ci_scripts` minimal, executable, fail-fast, and free of `sudo`.
- [ ] Store any necessary cloud environment secrets as redacted values; prefer no
  repository or workflow secrets for the pure-Swift build.
- [ ] Upload build, test, analysis, and archive-inspection evidence.
- [ ] Download and retain release-candidate artifacts and evidence beyond Xcode
  Cloud's artifact retention period.
- [ ] Make the relevant Xcode Cloud verification a required GitHub merge check.
- [ ] Reserve `ios-v...` tag patterns without enabling iOS distribution yet.

## 11. Hardware release matrix

- [ ] Write a versioned, operator-readable hardware validation procedure.
- [ ] List supported card generations and reader models without card identifiers.
- [ ] Record credential-free preflight and postflight retry state.
- [ ] Verify card and certificate discovery on each supported profile.
- [ ] Verify a local cryptographic signature against the published certificate.
- [ ] Verify client authentication in every declared supported system consumer.
- [ ] Verify PIN1 prompt suppression during an eligible cache window.
- [ ] Verify expiry 15 minutes after last successful cached use.
- [ ] Verify no cache at any non-5/5/5 state.
- [ ] Verify the operation at three attempts can make at most one card attempt
  and that no PIN operation is offered at two or fewer attempts.
- [ ] Do not deliberately exercise a real card's final attempt.
- [ ] Verify removal, reinsertion, same-reader swap, reader contention, sleep,
  wake, extension restart, app restart, and Mac restart behavior.
- [ ] Test supported Intel and Apple Silicon Macs if both are declared supported.
- [ ] Retain a sanitized signed result tied to source commit and cloud build.

## 12. TestFlight

- [ ] Create an internal macOS tester group.
- [ ] Add test information, feedback address, and focused what-to-test notes.
- [ ] Produce the first `macos-vYY.M.D-dev.<build>` build through Xcode Cloud.
- [ ] Resolve all internal release blockers.
- [ ] Create the external tester group and supply Beta App Review information.
- [ ] Record encryption/export-compliance answers for the build.
- [ ] Attach a physical hardware demonstration video without credentials or PII.
- [ ] Decide whether App Review needs a dedicated nonproduction card and reader;
  keep any review PIN outside source, issues, logs, and recordings.
- [ ] Produce and approve the first `macos-vYY.M.D-beta.<build>` build.
- [ ] Exercise install, upgrade, downgrade refusal where applicable, and clean
  uninstall through TestFlight/App Store behavior.
- [ ] Produce the `macos-vYY.M.D-rc.<build>` candidate only after software and
  hardware gates pass.
- [ ] Freeze the tested candidate build for App Store submission.

## 13. App Store metadata and review

- [ ] Publish privacy policy, support, and security pages on `www.refineid.fi`.
- [ ] Audit actual app and dependency behavior before selecting App Privacy
  answers; claim "Data Not Collected" only if evidence supports it.
- [ ] Complete privacy policy URL, app privacy, age rating, category, pricing,
  availability, and export-compliance fields.
- [ ] Confirm the public developer/seller name and EU trader disclosures match the
  approved release decision.
- [ ] Write accurate Finnish, Swedish, and English name, subtitle, description,
  keywords,
  release notes, and support text.
- [ ] Capture App Store screenshots with synthetic or redacted data.
- [ ] Verify the icon and screenshots against current Apple requirements.
- [ ] Write review notes explaining the CTK extension and system-wide utility.
- [ ] Provide exact reader/card setup and a useful no-card review path.
- [ ] Attach a video showing physical hardware and the complete authentication
  flow without revealing the PIN or cardholder information.
- [ ] Explain the intentionally excluded management, portrait, signature-image,
  CLI, remote, and iOS features; ship no hidden mode.
- [ ] Select the exact tested release-candidate build in App Store Connect.
- [ ] Submit manually to App Review and respond to review questions with retained
  evidence.
- [ ] Create the final `macos-vYY.M.D` tag at the candidate source commit.
- [ ] Use manual release after approval and record the release decision.

## 14. Final archive audit

- [ ] Confirm the archive is sandboxed and has only reviewed entitlements.
- [ ] Confirm the CTK extension is embedded and signed by the same team.
- [ ] Confirm app and extension versions and bundle identifiers match the release
  record.
- [ ] Confirm all declared Mac architectures and minimum OS settings.
- [ ] Confirm the privacy manifest is present and valid.
- [ ] Confirm no file in the archive has a quarantine extended attribute.
- [ ] Confirm there are no helper tools, Rust libraries, install scripts,
  provisioning profiles, writable executable resources, or unexpected dylibs.
- [ ] Confirm release logging is privacy-safe and debug switches are disabled.
- [ ] Confirm the source tree and generated archive contain no secrets or PII.
- [ ] Confirm the exact archive has passed TestFlight and hardware validation.

## 15. Release and post-release

- [ ] Publish v1.0 support and known-limitations pages before manual release.
- [ ] Record source tag, Xcode Cloud build, App Store build, hardware evidence,
  metadata revision, and approver in the release record.
- [ ] Monitor App Store review messages, crash reports, TestFlight/App Store
  feedback, and security reports without adding tracking to the app.
- [ ] Define criteria for pausing release and for an emergency update.
- [ ] Confirm users can remove the driver by removing ReFineID.app.
- [ ] Triage v1.1 candidates separately: PIN changes, activation, and PUK unblock.
- [ ] Review the retry and cache policy after real-world evidence; do not weaken it
  through an unreviewed hotfix.

## 16. iOS release

- [ ] Reproduce attached-reader token minting and the Safari client-cert
  login under the release team with App-Store-shaped signing; no restricted
  entitlements are required for this path (`Documentation/ios-product-plan.md`
  P0 gate 1). Development-signed reproduction complete 2026-07-22 - native
  Safari suomi.fi login with the system PIN prompt on the release team's
  identifiers; the distribution-signed reproduction remains.
- [ ] Decide and validate the shippable DVV trust-chain onboarding, including
  App Review acceptability of the configuration-profile guidance (P0 gate 2).
- [ ] Reproduce the verified Safari client-cert login purely from the
  App-Store-shaped build with the CTK extension publishing the identity
  (P0 gate 3).
- [ ] Decide the supported reader list and USB-C-only boundary (P0 gate 4).
- [ ] Record the export-compliance answers for a pure-Swift artifact that
  ships no own cryptography before the first TestFlight build (P0 gate 5).
- [ ] Submit the NFC CTK-registration Feedback to Apple and track the
  dependency without blocking v1 (P0 gate 6).
- [ ] Create the iOS target, App Store record, hardware matrix, and review
  package once the P0 gates have recorded evidence.
- [ ] Add `ios-v*-dev.*`, `ios-v*-beta.*`, and `ios-v*-rc.*` workflows without
  changing macOS release triggers.
- [ ] Maintain old release branches only when a supported old version actually
  needs patches; do not create permanent platform integration branches.
