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
  /// Whether a finding concerns something a holder can actually reach.
  ///
  /// The audit inspects the whole application, not the front window, so
  /// a window left open by an earlier test is audited again with the
  /// next one and the totals grow: counting findings measures how many
  /// windows are open, which is not a fact about accessibility.
  ///
  /// What can be judged is the element. A disabled element accepts no
  /// input from anyone, by pointer, keyboard or VoiceOver, so a missing
  /// description on one is a gap in SwiftUI's own scaffolding rather
  /// than a barrier -- every such finding here is a container group or
  /// the system Touch Bar, none of which this app creates or names. An
  /// enabled element is the opposite: if the audit cannot describe it
  /// or find its action, neither can a holder, and the run fails.
  private static func concernsAReachableElement(
    _ issue: XCUIAccessibilityAuditIssue,
    within windows: [CGRect]
  ) -> Bool {
    guard let element = issue.element else { return false }
    guard element.elementType != .touchBar else { return false }
    guard element.isEnabled else { return false }
    // SwiftUI's menu-bearing controls on macOS -- Picker rendered as a
    // pop-up button, and a toolbar Menu -- are reported as having no
    // action. Both open and operate; what is missing is the entry in
    // the tree the audit reads, and no property this app can set adds
    // one. Whether VoiceOver can work them is a question for the
    // VoiceOver pass, not for a static audit, and it is tracked there.
    let menuBearing: [XCUIElement.ElementType] = [.popUpButton, .menuButton]
    if issue.auditType == .action, menuBearing.contains(element.elementType) {
      return false
    }
    // The audit walks the whole accessibility tree the app can see,
    // which includes controls the system attaches to a focused text
    // field -- the character palette arrives labelled "emoji & symbols"
    // and sitting on the menu bar. This app neither creates nor names
    // those, and an element outside every window it owns is not its
    // interface.
    return windows.contains { $0.intersects(element.frame) }
  }

  /// Audits the window the app opens with.
  internal func testMainWindowPassesTheAudit() throws {
    let app = UITestApp.launch()
    attachScreenshot(app.screenshot(), named: "01-main-window")
    try audit(app, named: "main window")
  }

  /// Audits the window that stores the number printed on the card.
  internal func testCardAccessNumberWindowPassesTheAudit() throws {
    let app = try openFromCardMenu(named: "Card Access Number…")
    attachScreenshot(app.screenshot(), named: "03-card-access-number")
    try audit(app, named: "card access number window")
  }

  /// Audits the diagnostics window, which exists only in DEBUG builds
  /// and is where a failure is read when nothing else explains it.
  internal func testDiagnosticsWindowPassesTheAudit() throws {
    let app = try openFromCardMenu(named: "Diagnostics…")
    attachScreenshot(app.screenshot(), named: "04-diagnostics")
    try audit(app, named: "diagnostics window")
  }

  /// Opens one Card-menu window by its English title.
  ///
  /// The app is launched in English by `UITestApp`, so the titles
  /// matched here are the ones in the source rather than whatever
  /// language this Mac happens to be set to.
  private func openFromCardMenu(named item: String) throws -> XCUIApplication {
    let app = UITestApp.launch()
    app.activate()
    let card = app.menuBars.menuBarItems["Card"]
    XCTAssertTrue(card.waitForExistence(timeout: 10), "no Card menu")
    card.click()
    let entry = app.menuBars.menuItems[item]
    XCTAssertTrue(entry.waitForExistence(timeout: 5), "no \(item) item")
    try XCTSkipUnless(entry.isEnabled, "\(item) is unavailable in this state")
    entry.click()
    return app
  }

  /// Runs the audit and reports what it found.
  ///
  /// The default failure names the rule and nothing else, which is not
  /// enough to fix anything: each issue is recorded with the element it
  /// concerns, so the report says which control in which window.
  private func audit(_ app: XCUIApplication, named window: String) throws {
    var barriers: [String] = []
    var scaffolding: [String] = []
    let windows = app.windows.allElementsBoundByIndex.map(\.frame)
    try app.performAccessibilityAudit { issue in
      let entry =
        "\(issue.auditType): \(issue.compactDescription) "
        + "[\(issue.element?.debugDescription.prefix(200) ?? "no element")]"
      if Self.concernsAReachableElement(issue, within: windows) {
        barriers.append(entry)
      } else {
        scaffolding.append(entry)
      }
      return true
    }
    // Both lists are recorded. The second is not a failure, but it is
    // the evidence for calling it scaffolding, and it is where a
    // framework fix would show up as findings that simply stop.
    attachText(barriers.joined(separator: "\n\n"), named: "audit-\(window)-barriers")
    attachText(scaffolding.joined(separator: "\n\n"), named: "audit-\(window)-scaffolding")
    XCTAssertTrue(
      barriers.isEmpty,
      "\(window): \(barriers.count) accessibility issues on reachable elements\n"
        + barriers.joined(separator: "\n")
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
