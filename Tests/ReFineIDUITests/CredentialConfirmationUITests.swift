// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import XCTest

/// The confirmation that stands between a filled-in management form and
/// the card.
///
/// WCAG 3.3.4 asks that an action with consequences be reversible,
/// checked, or confirmed. A retry counter is none of the first two, so
/// these tests hold the third: the operation is announced before it is
/// sent, and abandoning it sends nothing.
///
/// Nothing here ever presses the confirming button. A run that did
/// would spend one of a real card's attempts on a made-up PIN, and a
/// test suite is not entitled to do that.
@MainActor
internal final class CredentialConfirmationUITests: XCTestCase {
  /// Digits that are certainly not this card's PIN, and are never
  /// sent: the form is abandoned while they are still on screen.
  private static let unusedEntry = "0000"

  /// Filling in a PIN change and pressing Change asks first, and the
  /// question names the credential rather than the task.
  internal func testChangingAPinAsksBeforeSpendingAnAttempt() throws {
    let app = try management()
    try fillChangeForm(app)
    app.buttons["managementChangePIN1"].click()
    let confirm = app.buttons[UITestIdentifiers.managementConfirm]
    XCTAssertTrue(
      confirm.waitForExistence(timeout: 5),
      "Change went to the card without asking"
    )
    attachScreenshot(app.screenshot(), named: "confirm-change-pin1")
    XCTAssertTrue(
      confirm.label.contains("PIN 1"),
      "the confirming button does not name the credential: \(confirm.label)"
    )
  }

  /// Cancelling leaves the card untouched and the form intact, so a
  /// holder who opened the question by reflex loses nothing.
  internal func testCancellingSendsNothingToTheCard() throws {
    let app = try management()
    try fillChangeForm(app)
    app.buttons["managementChangePIN1"].click()
    let cancel = app.buttons[UITestIdentifiers.managementCancel]
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), "no way to abandon the operation")
    cancel.click()
    XCTAssertFalse(
      app.buttons[UITestIdentifiers.managementConfirm].waitForExistence(timeout: 2),
      "the question stayed open after it was abandoned"
    )
    // The entries survive, so correcting one digit does not mean
    // typing all three fields again.
    XCTAssertTrue(
      app.buttons["managementChangePIN1"].isEnabled,
      "the form was cleared by a cancelled operation"
    )
  }

  /// Opens the management window, or skips when no card is present.
  private func management() throws -> XCUIApplication {
    let app = UITestApp.launch()
    let button = app.buttons[UITestIdentifiers.pinManagementButton]
    try XCTSkipUnless(
      button.waitForExistence(timeout: 10),
      "no card present; management window unavailable"
    )
    button.click()
    let action = app.descendants(matching: .any)[UITestIdentifiers.managementTask]
    XCTAssertTrue(action.waitForExistence(timeout: 10), "management window did not open")
    return app
  }

  /// Fills the PIN1 change form with entries that are never sent.
  private func fillChangeForm(_ app: XCUIApplication) throws {
    let fields = ["Current", "New", "Repeat"].map { suffix in
      app.secureTextFields["managementChangePIN1\(suffix)"]
    }
    try XCTSkipUnless(
      fields[0].waitForExistence(timeout: 5),
      "the window did not open on Change PIN 1"
    )
    for field in fields {
      field.click()
      field.typeText(Self.unusedEntry)
    }
  }
}
