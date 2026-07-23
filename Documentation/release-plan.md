# Apple App Store release plan

Last reviewed: 2026-07-23

This document defines the product, security, validation, and distribution gates
for the Swift ReFineID release. [TASKS.md](../TASKS.md) is the
checkable execution list. If the two documents disagree, this plan controls until
the disagreement is resolved in a reviewed change.

## Release objective

Ship a small, trustworthy macOS App Store product named **ReFineID**.

The application contains the CryptoTokenKit smart-card extension that
xOS loads for a supported card.

User story is:

1. Install ReFineID from the Mac App Store.
2. Insert supported Finnish identity card into a reader.
3. Open ReFineID and see that the extension, reader, and card are available.
4. See PIN1, PIN2, and PUK retry state.
5. Use the card's authentication certificate in a system CryptoTokenKit client.
6. Enter PIN1 through the system authentication flow when required.

## Product

### Included

- A sandboxed, native Swift macOS application.
- A native Swift CryptoTokenKit smart-card token extension embedded in the app.
- Supported-card, reader, extension, and application version status.
- Display of PIN1, PIN2, and PUK attempts remaining.
- Publication of the card's PIN1 authentication identity to macOS.
- PIN1-gated authentication signatures for the explicitly supported card and
  key profiles.
- A memory-only, card-bound PIN1 convenience cache
- Clear no-card, unsupported-card, low-retry, locked-card, and uncertain-state
  guidance in Finnish, Swedish, and English.

### Excluded

- The `refineid` command line tool or any command line installer.
- Rust libraries, Rust runtime code, helper executables, daemons, or privileged
  helpers in the App Store artifact.
- Card activation, PIN changes, and PUK unblock operations.
- PIN2 qualified-signature operations until separately specified and reviewed.
- Portrait and stored handwritten-signature display.
- Safari extensions, browser shells, login relays, remote-card operation, NFC,
  telemetry, analytics, accounts, and cloud services.
- iOS distribution.

PIN and PUK management will be later added to the same native application.

### Delivery sequence

| Milestone | Outcome |
| --- | --- |
| M4 - Release evidence | Security, clean-archive, accessibility, clean-Mac, and real-card hardware matrices pass for an exact cloud build. |
| M5 - TestFlight | Explicit development, beta, and release-candidate tags distribute through the configured tester groups. |
| M6 - App Store | The exact tested candidate passes App Review and is released manually with public source and support ready. |

## Architecture

The production archive has one containing application and one embedded app
extension:

```text
ReFineID.app
|-- Contents/MacOS/ReFineID
|-- Contents/PlugIns/ReFineIDTokenExtension.appex
`-- Contents/Resources/...
```

The repository keeps a stable Xcode project or workspace in version control.
It must not depend on a project generator during Xcode Cloud onboarding or
release builds.

The Swift implementation follows the Rust reference implementation.

### Retry floor

Immediately before every CTK PIN-bearing command, obtain retry state without
sending a credential. Perform the check and credential command in one exclusive
card transaction where the platform permits it.

- Three or more attempts remaining: the CTK operation may proceed.
- One or two attempts remaining: refuse before prompting for or sending the PIN.
- Zero attempts remaining: report the credential as blocked.
- Missing, malformed, stale, or unreadable retry state: reject attempt to talk to card.
- CTK has no expert override.

If a wrong PIN sent at three attempts leaves two attempts, clear positive PIN
state and refuse every later CTK PIN operation. CTK must never consume the last
attempt and never sends a PIN when only one or two attempts remain.
Read-only status and certificate inspection remain available when safe.

### PIN1 cache

Caching PIN1 (never cache PIN2) is permitted only while the live retry state is
exactly PIN1/PIN2/PUK = 5/5/5. Represent this as a named `pristine` domain state
rather than three repeated integer comparisons.

## User experience

The clean-machine trust story is part of this experience. The Store app neither
uses administrator authorization nor silently modifies system trust settings.

The application uses native SwiftUI and AppKit only where SwiftUI does not expose
the required macOS behavior. It supports keyboard navigation, VoiceOver,
increased contrast, reduced motion, text scaling where applicable, and clear
focus and error states. The icon follows the current Apple Human Interface
Guidelines and is built from owned source artwork.

### Calendar versioning

- **Version (`CFBundleShortVersionString`):** `YY.M.D` of the release day in
  Europe/Helsinki local time, without zero padding, for example `26.7.23`.
  Apple accepts at most three period-separated integers, so the year owns the
  first component and at most one App Store release ships per day.
- **Build number (`CFBundleVersion`):** the ten-minute bucket of Helsinki local
  time at which the build was cut: hour times ten plus the tens digit of the
  minute. `130` means 13:00-13:09; `93` means 09:30-09:39. At most one build
  per bucket. Buckets increase strictly within a day. Build numbers restart
  each day, which is valid because App Store Connect requires build-number
  uniqueness only within one version string and the version changes daily.
- TestFlight and App Store Connect display the pair as `26.7.23 (130)`.

Xcode Cloud owns App Store signing. The repository contains no certificate
private keys, provisioning profiles, API keys, or Apple account credentials.
Secret environment values, if ever required, are redacted in Xcode Cloud.

## Apple references

- [CryptoTokenKit](https://developer.apple.com/documentation/cryptotokenkit)
- [`TKSmartCardTokenDriver`](https://developer.apple.com/documentation/cryptotokenkit/tksmartcardtokendriver)
- [Creating a smart-card app extension](https://developer.apple.com/documentation/cryptotokenkit/authenticating-users-with-a-cryptographic-token)
- [Smart-card entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.smartcard)
- [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [Configuring macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Setting up Xcode Cloud](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud)
- [Xcode Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference)
- [Writing Xcode Cloud custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [Preparing hardware-dependent apps for App Review](https://developer.apple.com/app-store/review/)
- [Managing App Store privacy information](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple app-icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Performing accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
- [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels/)
