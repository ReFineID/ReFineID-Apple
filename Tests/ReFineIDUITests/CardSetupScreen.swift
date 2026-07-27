import XCTest

/// The setup screen, driven the way a holder drives it: type into the
/// field, press the button under it, read the line that replaces both.
///
/// It is a page object rather than a test so that the priming test can
/// bring a device up to a known state without depending on the setup test
/// having run first. Cross-test ordering is not something XCTest promises,
/// and a device round trip is too expensive to spend discovering that.
///
/// Nothing here attaches, prints or returns the digits it is given. Every
/// method answers with a yes or a no about what the screen ended up
/// showing.
@MainActor
internal enum CardSetupScreen {
  /// One credential row, named by the identifiers that drive it.
  ///
  /// A row is four identifiers that always travel together, and passing
  /// them one by one made a six-parameter function that could be called
  /// with two of them swapped.
  internal struct Row {
    /// The card access number row.
    internal static let cardAccessNumber = Self(
      status: UITestIdentifiers.cardAccessNumberStatus,
      replace: UITestIdentifiers.replaceCardAccessNumber,
      field: UITestIdentifiers.cardAccessNumberField,
      save: UITestIdentifiers.saveCardAccessNumber)

    /// The PIN1 row.
    internal static let pin1 = Self(
      status: UITestIdentifiers.pin1Status,
      replace: UITestIdentifiers.replacePin1,
      field: UITestIdentifiers.pin1Field,
      save: UITestIdentifiers.savePin1)

    /// Identifier of the line shown once a value is stored.
    internal let status: String

    /// Identifier of the button that clears a stored value.
    internal let replace: String

    /// Identifier of the entry field, present only while nothing is
    /// stored.
    internal let field: String

    /// Identifier of the button that stores what was typed.
    internal let save: String
  }

  /// How long a row takes to appear after a tap.
  private static let appearTimeout: TimeInterval = 10

  /// How many times the form is scrolled to reach a control.
  ///
  /// A number pad has no dismiss key, so the button that stores what was
  /// just typed can sit under the keyboard on a small screen. Scrolling is
  /// what a holder would do; a bound stops it becoming an infinite loop
  /// when the control is missing for some other reason.
  private static let scrollAttemptLimit: Int = 6

  /// Whether both credentials currently read as stored.
  internal static func credentialsStored(in app: XCUIApplication) -> Bool {
    Self.element(Row.cardAccessNumber.status, in: app).exists
      && Self.element(Row.pin1.status, in: app).exists
  }

  /// Puts `digits` into one row, clearing whatever was there first.
  ///
  /// Replacing rather than trusting what the device already holds is
  /// deliberate: a run that silently kept yesterday's access number would
  /// report a green setup for a card it never touched.
  ///
  /// Returns whether the row ended up reading as stored.
  internal static func store(
    _ digits: String,
    into row: Row,
    in app: XCUIApplication
  ) -> Bool {
    if Self.element(row.status, in: app).exists {
      guard Self.tap(app.buttons[row.replace], in: app) else { return false }
    }
    let field = Self.element(row.field, in: app)
    guard field.waitForExistence(timeout: Self.appearTimeout) else { return false }
    field.tap()
    field.typeText(digits)
    guard Self.tap(app.buttons[row.save], in: app) else { return false }
    return Self.element(row.status, in: app).waitForExistence(timeout: Self.appearTimeout)
  }

  /// An element by identifier, whatever kind of element the platform made
  /// of it.
  ///
  /// A `LabeledContent` in a form is not reliably a static text, a cell or
  /// a button across releases, and a query that names the kind breaks on
  /// the release that changes its mind.
  private static func element(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  /// Taps a control, scrolling it out from under the keyboard if it has
  /// to.
  private static func tap(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    guard element.waitForExistence(timeout: Self.appearTimeout) else { return false }
    var remaining = Self.scrollAttemptLimit
    while !element.isHittable, remaining > 0 {
      app.swipeUp()
      remaining -= 1
    }
    guard element.isHittable else { return false }
    element.tap()
    return true
  }
}
