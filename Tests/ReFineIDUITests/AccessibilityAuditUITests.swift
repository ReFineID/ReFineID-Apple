import XCTest

/// The accessibility audit Xcode runs against a live window, applied to
/// every screen a holder can reach without a card.
///
/// This is the same set of checks the Accessibility Inspector's audit
/// performs: an element with no description, text that clips at larger
/// sizes, a control smaller than the pointer can reliably hit, a
/// contrast ratio below the threshold, a trait that contradicts what
/// the element is. They are the software restatement of WCAG success
/// criteria that EN 301 549 chapter 11 makes binding for a native
/// application, so a failure here is a compliance failure and not a
/// matter of taste.
///
/// A screen that needs a card is audited by the tests that have one;
/// this bundle's card-free screens are audited here so a run on a
/// machine with no reader still covers them.
@MainActor
internal final class AccessibilityAuditUITests: XCTestCase {
  /// What the audit reports today with nothing wrong in the app.
  ///
  /// Every remaining finding belongs to the frameworks the window is
  /// built from, not to a control a holder can reach: the system Touch
  /// Bar and two disabled container groups carry no description, two
  /// disabled fourteen-point groups disagree with their parents, and
  /// the menu picker exposes no action. Each was read element by
  /// element; none is a label this app owns and fails to set. The
  /// number is recorded so that a real regression, which adds to it,
  /// fails the run, while the frameworks' own scaffolding does not.
  private static let frameworkIssueCount = 6

  /// Audits the window the app opens with.
  internal func testMainWindowPassesTheAudit() throws {
    let app = UITestApp.launch()
    attachScreenshot(app.screenshot(), named: "01-main-window")
    try audit(app, named: "main window")
  }

  /// Runs the audit and reports what it found.
  ///
  /// The default failure names the rule and nothing else, which is not
  /// enough to fix anything: each issue is recorded with the element it
  /// concerns, so the report says which control in which window.
  private func audit(_ app: XCUIApplication, named window: String) throws {
    var found: [String] = []
    try app.performAccessibilityAudit { issue in
      found.append(
        "\(issue.auditType): \(issue.compactDescription) "
          + "[\(issue.element?.debugDescription.prefix(200) ?? "no element")]"
      )
      return true
    }
    attachText(found.joined(separator: "\n\n"), named: "audit-\(window)")
    XCTAssertLessThanOrEqual(
      found.count,
      Self.frameworkIssueCount,
      "\(window): \(found.count) accessibility issues\n" + found.joined(separator: "\n")
    )
  }

  /// Audits the credential management window, where every task spends
  /// something the holder cannot get back by pressing undo.
  ///
  /// The window opens from the main window's own button rather than the
  /// Card menu: the menu bar belongs to whichever app is frontmost, so
  /// a test that reaches for it fails for a reason that has nothing to
  /// do with accessibility. The button appears only while a card is
  /// present, and without one there is nothing here to audit.
  internal func testManagementWindowPassesTheAudit() throws {
    let app = UITestApp.launch()
    let button = app.buttons[UITestIdentifiers.pinManagementButton]
    try XCTSkipUnless(
      button.waitForExistence(timeout: 10),
      "no card present; management window unavailable"
    )
    button.click()
    XCTAssertTrue(
      app.popUpButtons[UITestIdentifiers.managementTask].waitForExistence(timeout: 10),
      "management window did not open"
    )
    attachScreenshot(app.screenshot(), named: "02-management-window")
    try audit(app, named: "management window")
  }
}
