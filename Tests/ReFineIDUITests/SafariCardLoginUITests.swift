import XCTest

/// The whole point, measured end to end: system Safari, a site that
/// REQUIRES a client certificate, and this phone's card answering the
/// challenge with no app of ours in the foreground.
///
/// Deliberately cross-app. Our app being absent is the point: the system
/// has to summon the NFC sheet itself for the token that priming
/// registered. Run the setup and priming tests first, leave the card
/// resting on the phone, and leave it there.
///
/// Two lessons are built in, each bought with a wasted run:
///
/// - The certificate picker and the NFC sheet are SPRINGBOARD's UI, not
///   Safari's. A search of Safari's element tree alone reports "no prompt"
///   while a prompt is plainly on screen, so this watches
///   `com.apple.springboard` as well and takes the affirmative action
///   there.
/// - Only a site that REQUIRES client authentication proves anything. An
///   optional-auth server lets Safari finish cert-less with a 403 and
///   never asks for a certificate at all, so it cannot answer whether
///   Safari would have offered the card. `card.refineid.fi` is
///   optional-auth; the default target and `suomi.fi` are not.
///
/// One site per run: the target and its success marker come from the
/// environment, so a second site is a second invocation, not a second copy
/// of this file.
///
/// Nothing here attaches page text. A signed-in page carries the holder's
/// name, and a text attachment is the kind of evidence that gets grepped,
/// pasted and mailed. The screenshots and the screen recording are the
/// record of what was on screen; the text summary stays facts about the
/// run.
@MainActor
internal final class SafariCardLoginUITests: XCTestCase {
  /// What one watch of the screen recorded, whichever way it ended.
  private struct Observation {
    /// Whether a system sheet or alert ever appeared.
    let sawCertificatePrompt: Bool

    /// Whether the system ever asked for the card.
    let sawScanSheet: Bool

    /// Whether the signed-in page was reached.
    let signedIn: Bool

    /// Every distinct system label the run met, in the order it met them.
    let systemLabels: [String]
  }

  /// System Safari.
  private static let safariBundleIdentifier = "com.apple.mobilesafari"

  /// The process that owns the certificate picker and the NFC sheet.
  private static let springboardBundleIdentifier = "com.apple.springboard"

  /// How long to allow for the sheet, PACE, PIN1 and the on-card
  /// signature.
  ///
  /// A measured in-app signature takes about eight seconds; the system
  /// sheet adds its own dwell, and a holder finding the spot adds more.
  private static let signTimeout: TimeInterval = 120

  /// How long to wait for Safari itself.
  private static let launchTimeout: TimeInterval = 30

  /// How long to wait for Safari's address field.
  private static let fieldTimeout: TimeInterval = 20

  /// Wait between two looks at the screen.
  private static let pollInterval: TimeInterval = 2

  /// How many system elements are read per look.
  ///
  /// The system tree is large and reading all of it costs more than the
  /// poll interval; the sheets this cares about put their text at the
  /// front.
  private static let systemElementLimit: Int = 12

  /// Apple's own title on the NFC sheet.
  private static let scanSheetTitle = "Ready to Scan"

  /// The affirmative action a holder would take on a system prompt.
  ///
  /// English only, and knowingly so: these are the system's own strings
  /// and there is no identifier to query them by. A device in another
  /// language still records the whole run in the screenshots and the
  /// recording, which is what the tap here exists to make watchable.
  private static let affirmativeActions = ["Allow", "Continue", "OK", "Select", "Use"]

  /// Whether the signed-in page is on screen.
  private static func signedIn(_ safari: XCUIApplication) -> Bool {
    safari.webViews.firstMatch.staticTexts
      .containing(NSPredicate(format: "label CONTAINS[c] %@", UITestEnvironment.successMarker))
      .firstMatch
      .exists
  }

  /// Whether the system is asking for the card.
  ///
  /// Checked in both trees: the sheet belongs to SpringBoard, but a
  /// release that hosted it differently would otherwise read as no sheet
  /// at all.
  private static func scanSheetVisible(
    _ safari: XCUIApplication,
    _ springboard: XCUIApplication
  ) -> Bool {
    springboard.staticTexts[Self.scanSheetTitle].exists
      || safari.staticTexts[Self.scanSheetTitle].exists
  }

  /// Whether a system sheet or alert is up.
  private static func systemPromptVisible(_ springboard: XCUIApplication) -> Bool {
    springboard.sheets.firstMatch.exists || springboard.alerts.firstMatch.exists
  }

  /// The labels the system is showing, so a run records what it met.
  private static func systemLabels(of springboard: XCUIApplication) -> [String] {
    let elements =
      springboard.buttons.allElementsBoundByIndex
      + springboard.staticTexts.allElementsBoundByIndex
    return
      elements
      .prefix(Self.systemElementLimit)
      .map(\.label)
      .filter { !$0.isEmpty }
  }

  /// Presses the button a holder would press on a system prompt.
  private static func takeAffirmativeAction(in springboard: XCUIApplication) {
    for name in Self.affirmativeActions where springboard.buttons[name].exists {
      springboard.buttons[name].tap()
      return
    }
  }

  /// Opens the card-authenticated site in Safari and reports what
  /// happened.
  internal func testSignsInWithTheCard() {
    let safari = XCUIApplication(bundleIdentifier: Self.safariBundleIdentifier)
    safari.launch()
    XCTAssertTrue(
      safari.wait(for: .runningForeground, timeout: Self.launchTimeout),
      "Safari did not come to the front")
    attachScreenshot(safari.screenshot(), named: "01-safari-launched")

    let address =
      safari.textFields["URL"].exists ? safari.textFields["URL"] : safari.textFields.firstMatch
    guard address.waitForExistence(timeout: Self.fieldTimeout) else {
      attachScreenshot(safari.screenshot(), named: "02-no-address-field")
      XCTFail("Safari showed no address field to type into")
      return
    }
    address.tap()
    address.typeText(UITestEnvironment.targetSite + "\n")
    attachScreenshot(safari.screenshot(), named: "02-site-requested")

    let observation = watch(safari)
    attachScreenshot(safari.screenshot(), named: "05-final")
    let summary = """
      site: \(UITestEnvironment.targetSite)
      certificate prompt seen: \(observation.sawCertificatePrompt)
      system NFC sheet seen: \(observation.sawScanSheet)
      success marker found: \(observation.signedIn)
      system labels seen: \(observation.systemLabels.joined(separator: " / "))
      """
    attachText(summary, named: "06-summary")
    attachText(AppDiagnostics.text(from: UITestApp.launch()), named: "07-diagnostics")

    // The signed-in page is the only success criterion. A failure here is
    // a real result, not a flake: it means Safari never completed a card
    // signature.
    XCTAssertTrue(
      observation.signedIn, "Safari did not reach the card-authenticated page.\n" + summary)
  }

  /// Watches Safari and SpringBoard until the login lands or time runs
  /// out, answering the prompts a holder would answer.
  private func watch(_ safari: XCUIApplication) -> Observation {
    let springboard = XCUIApplication(bundleIdentifier: Self.springboardBundleIdentifier)
    var sawCertificatePrompt = false
    var sawScanSheet = false
    var labels: [String] = []
    let deadline = Date().addingTimeInterval(Self.signTimeout)
    while Date() < deadline, !Self.signedIn(safari) {
      for label in Self.systemLabels(of: springboard) where !labels.contains(label) {
        labels.append(label)
        attachScreenshot(springboard.screenshot(), named: "sb-\(labels.count)-\(label)")
      }
      if !sawScanSheet, Self.scanSheetVisible(safari, springboard) {
        sawScanSheet = true
        attachScreenshot(springboard.screenshot(), named: "03-nfc-sheet")
      }
      if Self.systemPromptVisible(springboard) {
        if !sawCertificatePrompt {
          sawCertificatePrompt = true
          attachScreenshot(springboard.screenshot(), named: "04-certificate-prompt")
        }
        Self.takeAffirmativeAction(in: springboard)
      }
      Thread.sleep(forTimeInterval: Self.pollInterval)
    }
    return Observation(
      sawCertificatePrompt: sawCertificatePrompt,
      sawScanSheet: sawScanSheet,
      signedIn: Self.signedIn(safari),
      systemLabels: labels)
  }
}
