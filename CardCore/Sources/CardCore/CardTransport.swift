/// A physical way of reaching the card.
///
/// The two transports differ in cost rather than capability. A reader is
/// passive, enumerable, and needs no card access number; the phone
/// antenna needs no hardware but seals the card's application until PACE
/// has run, so it asks the holder for a CAN and for several seconds of
/// stillness.
///
/// Raw values are persisted in the transport preference and must stay
/// stable across releases.
public enum CardTransport: String, CaseIterable, Equatable, Sendable {
  /// The phone's own antenna: contactless, iOS 26 and later only.
  ///
  /// macOS has no NFC smart-card slot at all, so this case is never
  /// supported there.
  case nearField = "near-field"

  /// A contact reader over USB, USB-C, or the platform's PC/SC stack.
  case reader = "reader"
}
