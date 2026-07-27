import XCTest

/// One hold of the card, run through the screen a holder would use, ending
/// in a card the system can ask for.
///
/// Registration is the assertion, not storage. A priming run that stores
/// the card details and then fails to register leaves a device that looks
/// set up and cannot log in, which is precisely the failure worth catching
/// -- so `primeStored` alone is not a pass.
///
/// The card must be resting on the phone before the run and stay there.
/// The test brings the device's credentials up to date first when the
/// environment carries them, so it does not depend on the setup test
/// having run before it: XCTest promises no ordering between classes, and
/// a device round trip is too expensive to spend learning that.
@MainActor
internal final class CardPrimingUITests: XCTestCase {
  /// How long one hold takes: the system sheet, PACE, two certificate
  /// reads, the serial, and the live registration behind them.
  private static let primeTimeout: TimeInterval = 180

  /// How long a screen takes to appear after a tap.
  private static let appearTimeout: TimeInterval = 15

  /// Brings the device's stored credentials up to date when the run was
  /// given them.
  ///
  /// Silent when it was not: a device that is already set up is a
  /// perfectly good subject for a priming run, and refusing to prime it
  /// would make this test unusable for the case it is most often wanted
  /// in.
  private static func storeCredentialsIfGiven(in app: XCUIApplication) {
    if let cardAccessNumber = UITestEnvironment.cardAccessNumber {
      _ = CardSetupScreen.store(cardAccessNumber, into: .cardAccessNumber, in: app)
    }
    if let pin1 = UITestEnvironment.pin1 {
      _ = CardSetupScreen.store(pin1, into: .pin1, in: app)
    }
  }

  /// Runs "Register this card" and asserts the card was registered.
  internal func testRegistersCardForSafari() {
    let app = UITestApp.launch()
    attachScreenshot(app.screenshot(), named: "01-setup-opened")
    Self.storeCredentialsIfGiven(in: app)

    let link = app.descendants(matching: .any)[UITestIdentifiers.registerCardLink]
    guard link.waitForExistence(timeout: Self.appearTimeout) else {
      attachScreenshot(app.screenshot(), named: "02-no-registration-row")
      attachText(AppDiagnostics.text(from: app), named: "03-diagnostics")
      XCTFail(
        "the setup screen offered no registration row, which means no card "
          + "access number is stored on this device")
      return
    }
    link.tap()

    let start = app.buttons[UITestIdentifiers.primeStartButton]
    guard start.waitForExistence(timeout: Self.appearTimeout), start.isEnabled else {
      attachScreenshot(app.screenshot(), named: "02-priming-unavailable")
      attachText(AppDiagnostics.text(from: app), named: "03-diagnostics")
      XCTFail(
        "the priming screen would not start: either the near-field transport "
          + "is switched off or no card access number is stored")
      return
    }
    attachScreenshot(app.screenshot(), named: "02-priming-screen")
    start.tap()

    let registered = app.descendants(matching: .any)[UITestIdentifiers.primeRegistered]
    let succeeded = registered.waitForExistence(timeout: Self.primeTimeout)
    attachScreenshot(app.screenshot(), named: "03-priming-result")
    let stored = app.descendants(matching: .any)[UITestIdentifiers.primeStored].exists
    attachText(AppDiagnostics.text(from: app), named: "04-diagnostics")
    XCTAssertTrue(
      succeeded,
      "the card was not registered for Safari (card details stored: \(stored)). "
        + "The attached diagnostics say what this device holds now.")
  }
}
