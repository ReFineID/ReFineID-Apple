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
  /// Audits the window the app opens with.
  internal func testMainWindowPassesTheAudit() throws {
    let app = UITestApp.launch()
    attachScreenshot(app.screenshot(), named: "01-main-window")
    try app.performAccessibilityAudit()
  }

  /// Audits the credential management window, where every task spends
  /// something the holder cannot get back by pressing undo.
  ///
  /// The window opens from the Card menu, which stays disabled while no
  /// card is present; without one there is nothing to audit and the
  /// test says so rather than passing on an empty screen.
  internal func testManagementWindowPassesTheAudit() throws {
    let app = UITestApp.launch()
    let item = app.menuBars.menuBarItems["Card"]
    XCTAssertTrue(item.waitForExistence(timeout: 10), "no Card menu")
    item.click()
    let management = app.menuBars.menuItems["PIN Management…"]
    XCTAssertTrue(management.waitForExistence(timeout: 5), "no management item")
    try XCTSkipUnless(management.isEnabled, "no card present; management window unavailable")
    management.click()
    attachScreenshot(app.screenshot(), named: "02-management-window")
    try app.performAccessibilityAudit()
  }
}
