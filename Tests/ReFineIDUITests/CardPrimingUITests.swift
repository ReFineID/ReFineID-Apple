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
#if os(iOS)

  import XCTest

  /// One setup run, keeping the card in place through the two system NFC
  /// fields, ending in a card the system can ask for.
  ///
  /// The holder-facing screen deliberately contains no progress or result
  /// report. The test therefore verifies the persistent CryptoTokenKit
  /// registration through the app's diagnostic report.
  ///
  /// The card must be resting on the phone before the run and stay there.
  /// The test brings the device's credentials up to date first when the
  /// environment carries them, so it does not depend on the setup test
  /// having run before it: XCTest promises no ordering between classes, and
  /// a device round trip is too expensive to spend learning that.
  @MainActor
  internal final class CardPrimingUITests: XCTestCase {
    /// How long the two-field setup takes: Core NFC PACE and metadata reads,
    /// followed by the live CryptoTokenKit registration field.
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
      _ = CardSetupScreen.enterCredentials(
        cardAccessNumber: UITestEnvironment.cardAccessNumber,
        pin1: UITestEnvironment.pin1,
        in: app)
    }

    /// Starts Safari setup from the card form and asserts registration.
    internal func testRegistersCardForSafari() {
      let app = UITestApp.launch()
      attachScreenshot(app.screenshot(), named: "01-setup-opened")
      Self.storeCredentialsIfGiven(in: app)

      let start = app.buttons[UITestIdentifiers.primeStartButton]
      guard start.waitForExistence(timeout: Self.appearTimeout), start.isEnabled else {
        attachScreenshot(app.screenshot(), named: "02-registration-unavailable")
        attachText(AppDiagnostics.text(from: app), named: "03-diagnostics")
        XCTFail(
          "Safari setup would not start: CAN or PIN1 is missing")
        return
      }
      attachScreenshot(app.screenshot(), named: "02-registration-ready")
      start.tap()

      _ = start.waitForNonExistence(timeout: Self.primeTimeout)
      attachScreenshot(app.screenshot(), named: "03-registration-finished")
      let diagnostics = AppDiagnostics.text(from: app)
      attachText(diagnostics, named: "04-diagnostics")
      XCTAssertTrue(
        diagnostics.contains("fi.refineid.ReFineID.token:"),
        "the card was not registered for Safari. "
          + "The attached diagnostics say what this device holds now.")
    }
  }

#endif
