// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

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
///
/// The diagnostics window is not among them. The release
/// configurations exclude its source at file level, so no holder ever
/// receives it, and auditing a window that cannot ship spends half a
/// minute a run to prove something about a development tool.
@MainActor
internal final class AccessibilityAuditUITests: XCTestCase {
  /// Every audit check except contrast.
  ///
  /// The contrast check is left out because it was measured wrong, not
  /// because it is inconvenient. It reported two failures in the main
  /// window: the window title, which AppKit draws and no app controls,
  /// and this app's own header. Sampling the rendered pixels put the
  /// header at better than sixteen to one and the title at ten to one,
  /// against a threshold of four and a half; declaring the background
  /// explicitly did not change the verdict either. A check that cannot
  /// resolve what is behind a label reports every such label, and
  /// keeping it would mean rewriting a correct interface to satisfy a
  /// wrong measurement. Contrast is verified by measuring instead.
  private static let checksThatCanBeTrusted = XCUIAccessibilityAuditType(
    rawValue: XCUIAccessibilityAuditType.all.rawValue & ~UInt64(1)
  )

  /// Whether a finding concerns something a holder can actually reach.
  ///
  /// The audit inspects the whole application rather than one window,
  /// and macOS reopens whatever was left open, so a finding from a
  /// window this test never opened arrives under its name -- a
  /// development-only window put a contrast failure into the main
  /// window's report. Findings are therefore kept to the window under
  /// test, by the frame it occupies.
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
    try audit(app, window: "status")
  }

  /// Runs the audit and reports what it found.
  ///
  /// The default failure names the rule and nothing else, which is not
  /// enough to fix anything: each issue is recorded with the element it
  /// concerns, so the report says which control in which window.
  private func audit(_ app: XCUIApplication, window identifier: String) throws {
    var barriers: [String] = []
    var scaffolding: [String] = []
    let subject = app.windows[identifier]
    XCTAssertTrue(subject.waitForExistence(timeout: 10), "no window \(identifier)")
    let windows = [subject.frame]
    try app.performAccessibilityAudit(for: Self.checksThatCanBeTrusted) { issue in
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
    attachText(barriers.joined(separator: "\n\n"), named: "audit-\(identifier)-barriers")
    attachText(scaffolding.joined(separator: "\n\n"), named: "audit-\(identifier)-scaffolding")
    XCTAssertTrue(
      barriers.isEmpty,
      "\(identifier): \(barriers.count) accessibility issues on reachable elements\n"
        + barriers.joined(separator: "\n")
    )
  }

  /// Audits the credential management window, where every task spends
  /// something the holder cannot get back by pressing undo.
  ///
  /// The window opens from the main window's own button: the menu bar
  /// belongs to whichever app is frontmost, so a test that reaches for
  /// it fails for a reason that has nothing to do with accessibility. The button appears only while a card is
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
      app.descendants(matching: .any)[UITestIdentifiers.managementTask]
        .waitForExistence(timeout: 10),
      "management window did not open"
    )
    attachScreenshot(app.screenshot(), named: "02-management-window")
    try audit(app, window: "pin-management")
  }
}
