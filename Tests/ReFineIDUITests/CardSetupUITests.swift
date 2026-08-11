//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
import XCTest

/// Card setup, driven the way a holder drives it: type the access number
/// and PIN1, then observe that the one minting action becomes available.
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

  /// Enters both credentials and asserts that identity creation is ready.
  internal func testAcceptsCredentialsForIdentityMinting() throws {
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

    let entered = CardSetupScreen.enterCredentials(
      cardAccessNumber: cardAccessNumber,
      pin1: pin1,
      in: app)
    attachScreenshot(app.screenshot(), named: "03-credentials-entered")
    XCTAssertTrue(
      entered,
      "one of the two credential fields could not be filled")

    let mint = app.buttons[UITestIdentifiers.primeStartButton]
    XCTAssertTrue(
      mint.waitForExistence(timeout: 10) && mint.isEnabled,
      "valid CAN and PIN1 did not enable identity minting")
  }
}
