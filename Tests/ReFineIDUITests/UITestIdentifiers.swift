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
/// `Sources/App/CardRegistrationSections.swift`,
/// `Sources/App/DiagnosticsView.swift`, and the card-management
/// sections under `Sources/App/`.
/// A UI test drives a separate process and cannot share a constant with
/// it, so this is the register that keeps the two sides honest.
internal enum UITestIdentifiers {
  /// The six-digit entry field, present until an identity is set.
  internal static let cardAccessNumberField = "cardAccessNumberField"

  /// The row that opens the diagnostics capture from setup.
  internal static let diagnosticsButton = "diagnosticsButton"

  /// The PIN1 entry field, present until an identity is set.
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

  /// The management window's task picker.
  internal static let managementTask = "managementTask"

  /// The management window's toolbar refresh.
  internal static let managementRefresh = "managementRefresh"

  /// The PIN1 change action; fields are Current/New/Repeat suffixed.
  internal static let managementChangePin1 = "managementChangePIN1"

  /// The PIN2 change action; fields are Current/New/Repeat suffixed.
  internal static let managementChangePin2 = "managementChangePIN2"

  /// The unblock action; Target/Puk/New/Repeat sit beside it.
  internal static let managementUnblock = "managementUnblock"

  /// The activation action; Entry/Pin1/Pin2 fields sit beside it.
  internal static let managementActivate = "managementActivate"
}
