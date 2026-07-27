import XCTest

/// Card setup, driven the way a holder drives it: type the access number,
/// type PIN1, save both, and read the rows back.
///
/// Both values come from the test runner's environment and neither is
/// written down here. A run given neither is not a quiet pass: it fails
/// and names the variable that was missing, because a green setup test
/// that never typed anything is worse than a red one.
@MainActor
internal final class CardSetupUITests: XCTestCase {
  /// What to say when the run was not given a value it cannot invent.
  ///
  /// The message names the exact placement, because the wrong one fails
  /// silently: appended after the arguments the assignment is taken as a
  /// build setting and never reaches the runner.
  private static func missing(_ variable: String) -> String {
    "\(variable) was not set on the test runner. Set it in xcodebuild's own "
      + "environment, BEFORE the command: "
      + "TEST_RUNNER_\(variable)=... xcodebuild test ... - not appended "
      + "after the arguments, and not as a plain exported variable."
  }

  /// Stores both credentials and asserts the screen reads them back as
  /// set.
  internal func testStoresCardAccessNumberAndPin1() throws {
    let cardAccessNumber = try XCTUnwrap(
      UITestEnvironment.cardAccessNumber,
      Self.missing(UITestEnvironment.cardAccessNumberVariable))
    let pin1 = try XCTUnwrap(
      UITestEnvironment.pin1,
      Self.missing(UITestEnvironment.pin1Variable))

    let app = UITestApp.launch()
    attachScreenshot(app.screenshot(), named: "01-setup-opened")
    // Sizes, never values: this is what catches a shell that ate a
    // leading zero, and it is all a result bundle may know about them.
    attachText(
      """
      card access number digits: \(cardAccessNumber.count)
      pin1 digits: \(pin1.count)
      """,
      named: "02-input-sizes")

    let storedCardAccessNumber = CardSetupScreen.store(
      cardAccessNumber, into: .cardAccessNumber, in: app)
    attachScreenshot(app.screenshot(), named: "03-card-access-number")
    XCTAssertTrue(
      storedCardAccessNumber,
      "the card access number row never came back reading as set")

    let storedPin1 = CardSetupScreen.store(pin1, into: .pin1, in: app)
    attachScreenshot(app.screenshot(), named: "04-pin1")
    XCTAssertTrue(storedPin1, "the PIN1 row never came back reading as set")

    let bothStored = CardSetupScreen.credentialsStored(in: app)
    attachText(AppDiagnostics.text(from: app), named: "05-diagnostics")
    XCTAssertTrue(bothStored, "setup finished with one of the two rows unset")
  }
}
