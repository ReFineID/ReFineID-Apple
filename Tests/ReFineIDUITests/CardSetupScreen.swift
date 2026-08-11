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

/// The setup screen, driven the way a holder drives it: enter both
/// credentials, then start the single identity-minting operation.
///
/// It is a page object rather than a test so that the priming test can
/// bring a device up to a known state without depending on the setup test
/// having run first. Cross-test ordering is not something XCTest promises,
/// and a device round trip is too expensive to spend discovering that.
///
/// Nothing here attaches, prints or returns the digits it is given.
@MainActor
internal enum CardSetupScreen {
  /// How long a control takes to appear after launch.
  private static let appearTimeout: TimeInterval = 10

  /// Enters whichever credentials are not already stored.
  ///
  /// A stored row has no field by design. In that case this leaves it
  /// alone; replacing a card is the explicit destructive action on the
  /// screen, not something automation should do implicitly.
  internal static func enterCredentials(
    cardAccessNumber: String?,
    pin1: String?,
    in app: XCUIApplication
  ) -> Bool {
    if let cardAccessNumber {
      guard
        Self.enter(
          cardAccessNumber,
          field: UITestIdentifiers.cardAccessNumberField,
          in: app
        )
      else { return false }
    }
    if let pin1 {
      guard
        Self.enter(
          pin1,
          field: UITestIdentifiers.pin1Field,
          in: app
        )
      else { return false }
    }
    return true
  }

  /// Enters one value into a field that is there until an identity is.
  private static func enter(
    _ digits: String,
    field fieldIdentifier: String,
    in app: XCUIApplication
  ) -> Bool {
    let field = app.descendants(matching: .any)[fieldIdentifier]
    guard field.waitForExistence(timeout: Self.appearTimeout), field.isHittable else {
      return false
    }
    field.tap()
    field.typeText(digits)
    return true
  }
}
