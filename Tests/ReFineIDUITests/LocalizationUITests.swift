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

/// The app in each language it claims to support.
///
/// A catalogue that compiles proves the file is well formed and nothing
/// else. What matters is that a holder who runs this Mac in Finnish or
/// Swedish is shown their own language, and that the window still works
/// when the words change length -- a translation that clips a button or
/// widens a window past the screen is a defect the English run cannot
/// show.
@MainActor
internal final class LocalizationUITests: XCTestCase {
  /// Clipped text, by the value the audit header assigns it.
  ///
  /// Swift does not surface it as a named member on macOS, so the
  /// option set is built from the documented bit position rather than
  /// left out of the run. Contrast is not asked for: see
  /// `AccessibilityAuditUITests` for what that check was measured
  /// doing.
  private static let clipping = XCUIAccessibilityAuditType(rawValue: 1 << 17)

  /// Finnish, and what PIN Management is called in it.
  internal func testTheAppSpeaksFinnish() {
    check(language: "fi", management: "PIN-koodien hallinta…")
  }

  /// Swedish, likewise.
  internal func testTheAppSpeaksSwedish() {
    check(language: "sv", management: "Hantering av PIN-koder…")
  }

  /// Finnish does not clip anything the English run sized.
  ///
  /// A Finnish or Swedish sentence is routinely longer than the English
  /// it was written from, and a control sized around the English one
  /// then clips it. This is the audit's own check for that, run in the
  /// language most likely to trip it.
  internal func testFinnishDoesNotClipTheWindow() throws {
    let app = UITestApp.launch(language: "fi")
    var clipped: [String] = []
    try app.performAccessibilityAudit(for: Self.clipping) { issue in
      // Asking for one check does not get one check: the run came back
      // with a parent/child mismatch, which is scaffolding and not a
      // translation that outgrew its control. What is kept is what was
      // asked for.
      guard issue.auditType == Self.clipping else { return true }
      clipped.append("\(issue.auditType): \(issue.compactDescription)")
      return true
    }
    attachText(clipped.joined(separator: "\n"), named: "clipping-fi")
    XCTAssertTrue(
      clipped.isEmpty,
      "Finnish clips the window:\n" + clipped.joined(separator: "\n")
    )
  }

  /// Launches in one language and reads the status window back.
  private func check(language: String, management: String) {
    let app = UITestApp.launch(language: language)
    app.activate()
    XCTAssertTrue(
      app.buttons[management].waitForExistence(timeout: 10),
      "PIN Management is not translated in \(language)"
    )
    attachScreenshot(app.screenshot(), named: "menu-\(language)")
    app.typeKey(.escape, modifierFlags: [])
  }
}
