import CardCore

/// Process-lifetime credential memory shared across token sessions.
///
/// A PIN the card rejected must not be resent for the extension's
/// lifetime, and token sessions come and go across card reinserts, so
/// this state lives at process scope (release plan section 4.3). It
/// holds only non-reversible fingerprints, never a PIN.
internal enum CredentialMemory {
  internal static let rejectedPins = RejectedPinMemory()

  /// The card-bound PIN1 cache: one PIN entry covers a login flow's signs.
  ///
  /// In-memory, zeroized, never persisted.
  internal static let pin1Cache = Pin1Cache()
}
