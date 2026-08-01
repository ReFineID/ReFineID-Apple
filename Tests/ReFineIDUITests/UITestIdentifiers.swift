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
/// `Sources/App/CardRegistrationSections.swift` and
/// `Sources/App/DiagnosticsView.swift`.
/// A UI test drives a separate process and cannot share a constant with
/// it, so this is the register that keeps the two sides honest.
internal enum UITestIdentifiers {
  /// The six-digit entry field, present until an identity is set.
  internal static let cardAccessNumberField = "cardAccessNumberField"

  /// The row that opens the diagnostics capture from setup.
  internal static let diagnosticsButton = "diagnosticsButton"

  /// The row saying a PIN1 is stored, present once one is.
  internal static let pin1Status = "pin1Status"

  /// The PIN1 entry field, present until one is stored.
  internal static let pin1Field = "pin1Field"

  /// The destructive action, present only while card state exists.
  internal static let forgetCardIdentityButton = "forgetCardIdentityButton"

  /// The line saying the identity is set, present once registered.
  internal static let identityStatus = "identityStatus"

  /// The button that starts one priming hold.
  internal static let primeStartButton = "primeStartButton"

  /// The minting action after its last attempt failed.
  internal static let primeFailed = "primeFailed"

  /// The button that temporarily reveals or conceals unsaved PIN1.
  internal static let pin1Visibility = "pin1Visibility"
}
