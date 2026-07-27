/// The accessibility identifiers these tests drive the app by.
///
/// Identifiers rather than labels, and that is not a preference. A label
/// is localized: on a phone set to Finnish every label query in this
/// bundle would miss, and the run would report a broken card path when the
/// only thing wrong was the device language. An identifier is the same
/// string in every language.
///
/// Each constant must match the `.accessibilityIdentifier(...)` of the
/// same spelling in `Sources/App/CardCredentialsView.swift`,
/// `Sources/App/CardPrimingView.swift` and `Sources/App/StatusView.swift`.
/// A UI test drives a separate process and cannot share a constant with
/// it, so this is the register that keeps the two sides honest.
internal enum UITestIdentifiers {
  /// The six-digit entry field, present only while nothing is stored.
  internal static let cardAccessNumberField = "cardAccessNumberField"

  /// The line saying a card access number is stored.
  internal static let cardAccessNumberStatus = "cardAccessNumberStatus"

  /// The row leading from setup to the card status screen.
  internal static let cardStatusLink = "cardStatusLink"

  /// The button that opens the diagnostics capture.
  internal static let diagnosticsButton = "diagnosticsButton"

  /// The PIN1 entry field, present only while nothing is stored.
  internal static let pin1Field = "pin1Field"

  /// The line saying a PIN1 is stored.
  internal static let pin1Status = "pin1Status"

  /// The result row shown when a priming run registered the card.
  internal static let primeRegistered = "primeRegistered"

  /// The button that starts one priming hold.
  internal static let primeStartButton = "primeStartButton"

  /// The result row shown when a priming run stored the card details.
  internal static let primeStored = "primeStored"

  /// The row leading from setup to the priming screen.
  internal static let registerCardLink = "registerCardLink"

  /// The button that clears a stored card access number.
  internal static let replaceCardAccessNumber = "replaceCardAccessNumber"

  /// The button that clears a stored PIN1.
  internal static let replacePin1 = "replacePin1"

  /// The button that stores the typed card access number.
  internal static let saveCardAccessNumber = "saveCardAccessNumber"

  /// The button that stores the typed PIN1.
  internal static let savePin1 = "savePin1"
}
