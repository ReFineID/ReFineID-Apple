# Apple release task list

Last reviewed: 2026-08-01



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
  `fi.refineid.ReFineID.token`); explicit App ID registration on the release
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
- [x] Implement supported RSA and ECC key profiles explicitly. ECC P-384 and
  RSA-2048/3072 are certificate-selected, published, and unit-tested; ECC is
  hardware-verified, while RSA qualified/PDF signing still needs the live-card
  check below.

- [x] Implement RSA/ECDSA result normalization and local signature verification.
  ECDSA `r||s` becomes X9.62 DER; RSA stays modulus-wide. Both fail closed on
  length or local-verification failure before a signature is returned.


## 5. Credential-command safety

- [ ] Re-key contactless identities by something card-unique. The ATR
  digest `CardInstanceIdentifier(answerToReset:)` uses is constant
  across a production batch, so two same-model cards on one device
  overwrite each other's primes and can be served each other's stored
  number and certificate. Bind the prime to the token serial once PACE
  has read it, and refuse a prime whose serial the card then
  contradicts.
- [ ] Add physical-transmit-count spies and tests around every credential path.
  `ScriptedChannel` asserts the exact transmit sequence for the read paths; a
  dedicated spy around the VERIFY path is still to add.
- [ ] Clear all credential state on ambiguous completion (cache clears on wrong
  PIN and card change; exhaustive ambiguous-completion coverage still to prove).

## 6. CTK extension

- [ ] Let the status screen say a stored number was refused, instead of
  the refusal being visible only in the log and the latch.
- [ ] Handle card removal, reinsertion, fast same-reader swap, reader contention,
  extension reuse, and extension termination (cache resets on a fresh token and
  the OS reaps the process; full matrix still to test).

## 6b. PKCS#11 bridge (PKCS11Bridge/)

- [ ] Publish every certificate the card carries, not the two the
  reader knows. `CardOperations` navigates to EF.4331 and EF.4332 and
  takes the key profile from whichever public key it finds, so one
  identity per PIN is published by construction. Identity cards issued
  between 11 January 2021 and 12 March 2023 carry two signature
  certificates, RSA and ECC
  (<https://dvv.fi/en/-/ecc-signature-certificates-on-identity-cards-issued-before-13-march-2023-will-be-centrally-revoked-the-revocation-does-not-affect-the-use-of-identity-cards>),
  and the same question stands for the later generation, whose cards
  may carry an RSA certificate beside the ECC one now published. Walk
  the PKCS#15 CIA object directory instead, which lists every
  certificate with a pointer to its key, rather than reading known
  locations.
- [ ] Withhold the ECC signature certificate on cards issued in that
  window: DVV revoked it centrally, so a signature made with it does
  not validate. The authentication certificate and the RSA signature
  certificate remain valid.
- [ ] Distinguish identities by algorithm once a card publishes more
  than one per PIN. The token names a key for the PIN it asks for, so
  two signature identities would carry the same name and the PKCS#11
  labels would collide.

Working read-and-sign module over CryptoTokenKit: full v3.2 surface,
slot/token enumeration, sessions, EC object model with CKA_ID pairing
and login-free certificates (Public Certificates Token behavior,
profiles v3.2), CKM_ECDSA signing via SecKeyCreateSignature with
DER-to-r||s conversion (pkcs11-curr v3.0), mechanisms clear of the
pkcs11-hist register. Hardware-proven: ssh-keygen -D lists both FINEID
card keys as ecdsa-sha2-nistp384, and an RSA-enrolled card through
CKM_RSA_PKCS with a signature openssl verifies. Remaining:

- [ ] Re-prove the ssh-agent path after the digest-algorithm fix
  (`ssh-add -s`, then a login). The `PKCS11Provider` path is proven
  against a real server, including an interactive login shell. Note
  when testing: `ssh-pkcs11-helper` keeps the module mapped for the
  agent's lifetime, so a reinstalled module needs `ssh-add -e` before
  `ssh-add -s`.
- [ ] Advertise the SHA-384 and SHA-512 PKCS#1 signing algorithms in
  the token extension. It offers only the SHA-256 and PSS variants, so
  an RSA card cannot serve the rsa-sha2-512 signature OpenSSH prefers
  and the bridge returns CKR_DATA_INVALID rather than a wrong
  signature; a per-host `PubkeyAcceptedAlgorithms rsa-sha2-256` is the
  workaround until then.
- [ ] Slot events: C_WaitForSlotEvent and token insertion/removal
  beyond per-call refresh.
- [ ] `keytool -list` through SunPKCS11 (CKA_ID strictness gate), then
  a PAdES signature from EU DSS via librefineid_pkcs11_sign.dylib,
  the name that exposes only the qualified-signature identity; the
  default name exposes only authentication identities
  (contentCommitment filter, disjoint profiles).
- [ ] Add the CKO_PROFILE object to the object model to complete
  Baseline Provider conformance (profiles v3.2); the interface surface
  it requires is already in place.
- [ ] Publish the issuer certificates the token carries as
  certificate objects without a paired key, so consumers that build
  chains -- Firefox, and DSS when it validates -- find them in the
  same place as the leaf.

Consumers need no smartcard entitlement to use this module: it reads
keychain token items and signs through SecKeyCreateSignature rather
than driving TKSmartCardSlot, which is what
`com.apple.security.smartcard` gates. Measured: none of OpenSSH's
PKCS#11 loaders carry that entitlement and all of them work. This is
what lets a hardened-runtime consumer such as the Java signing
application use the card without one.
- [ ] Ship both modules inside the app bundle
  (`Contents/Frameworks/`), built and signed with the app, so the App
  Store updates them and they stay matched to the token extension.
  That serves every consumer that takes a module path -- ssh
  `PKCS11Provider`, Firefox, SunPKCS11 -- with no installation at all.
- [ ] Ship a trampoline for `ssh-agent`, the one consumer that
  restricts module paths. Two measured obstacles rule out the simple
  answers. The agent resolves a path before matching its allowlist, so
  a symlink from `/usr/local/lib` into the app bundle is refused by
  its target. OpenSSH then reads the module file and requires
  `C_GetFunctionList` in that file's own symbol table before loading
  it, so a stub that re-exports the symbol from another library --
  where the linker records the delegation and the stub exports
  nothing -- is refused as "not a PKCS11 library". A stub that instead
  defines the discovery entry points as real functions, each calling
  `dlopen` and `dlsym` on the bundle module and forwarding, satisfies
  both: enumeration, agent loading, and a card-signed login are proven
  with the module in an `/Applications` bundle.

  The division of labour: the App Store delivers and updates the
  module inside the app, and the holder installs the stub once with
  admin rights, which a sandboxed app cannot do for them. App updates
  replace the implementation behind the stub, so there are no stale
  copies to support, and the stub itself changes only if the discovery
  entry points or the bundle path do.

  Forward all three discovery entry points, probe both `/Applications`
  and `~/Applications`, and fail with a legible message. Have the
  installer report the installed stub and the module it resolves to,
  so a mismatch is visible rather than mysterious.

  Signing does not block the load: both loaders disable library
  validation by entitlement -- `ssh-pkcs11-helper` holds
  `com.apple.security.cs.disable-library-validation` and
  `ssh-apple-pkcs11` holds
  `com.apple.private.security.clear-library-validation` -- because a
  PKCS#11 consumer must be able to load third-party modules at all.
  The ad-hoc signatures measured here have no team identity and would
  be the first thing library validation rejected, so an App Store
  signature cannot fail where they succeeded.

  That is also why the stub must check the signature itself. With
  validation off, the agent's path allowlist is the control, and it
  holds because `/usr/local/lib` is root-owned -- which is why the
  agent resolves symlinks before matching, so a root-owned name cannot
  point at a user-writable file. A stub loading from
  `/Applications` widens that boundary, the directory being
  admin-writable rather than root-owned. Before `dlopen`, verify the
  target with `SecStaticCodeCheckValidity` against a requirement
  pinning the team identifier and bundle identifier, so the stub
  enforces what library validation would have.
- [ ] `/usr/local/lib` stays the source-checkout install path.

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

- [ ] Name the status row's forget action honestly. It offers only
  "Replace", which forgets immediately even when nothing is re-entered;
  the Card menu's directory has honest Delete and Forget, the row does
  not yet.
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
- [ ] Link to issuer recovery guidance alongside the app's own unblock flow.
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
- [ ] Confirm v1.0 has no portrait or stored handwritten-signature UI.
- [ ] Hardware-verify the management window: activation preflight on both
  schemes, change and unblock floors, and that no operation runs below
  three attempts.
- [ ] Hardware-verify the qualified identity: per-signature PIN2 prompt with
  no cache, and a real qualified signature in a consuming application.

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
- [x] Test RSA and ECC signature inputs, output encodings, local verification,
  certificate/profile binding, and exact CMS signature fields.
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
- [ ] Explain the management features and the intentionally excluded portrait,
  signature-image, CLI, remote, and iOS features; ship no hidden mode.
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
- [ ] Review the shipped management flows against field evidence.
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
- [x] NFC CTK registration Feedback: withdrawn 2026-07-25, do not file.
  Registration was falsified 2026-07-24 and NFC sign completion on
  2026-07-25 (card signs the TLS CertificateVerify; HTTP 200). Nothing
  in that draft is Apple-side. See `Documentation/card-transports.md`.
- [ ] Port the pure-Swift PACE + secure messaging into CardCore so the
  contactless interface can be opened at all (the card seals PKCS#15
  until PACE runs). Donor: `ReFineID-iOS-Browser`
  `Sources/ReFineIDBrowserKit/Card`, Foundation/CryptoKit/CommonCrypto
  only. Gate: the synthetic-card round-trip test passes offline before
  any hardware is involved.
- [ ] Fix `BinaryReadAssembler`'s short-chunk end-of-file rule before the
  contactless path uses it: under secure messaging every chunk is short,
  so certificates would truncate silently rather than fail.
- [ ] Add the near-field slot, priming, and prime store on iOS, and the
  extension's contactless sign branch (PACE, then the existing PIN1 and
  signature chain). Keep the contact path byte-for-byte unchanged.
- [ ] Honour the transport preference in `TokenDriver` before creating a
  token, and in the reader-enumeration probes.
- [ ] Create the iOS target, App Store record, hardware matrix, and review
  package once the P0 gates have recorded evidence.
- [ ] Add `ios-v*-dev.*`, `ios-v*-beta.*`, and `ios-v*-rc.*` workflows without
  changing macOS release triggers.
- [ ] Maintain old release branches only when a supported old version actually
  needs patches; do not create permanent platform integration branches.
