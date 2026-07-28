/// The CryptoTokenKit namespace owned by ReFineID.
///
/// The driver class identifier is fixed by the extension manifest. Keeping
/// its token-ID spelling here gives the app and extension one source of truth
/// for registration, status, and revocation.
public enum CardTokenNamespace {
  /// The token driver's class identifier.
  public static let driverClassIdentifier = "fi.refineid.ReFineID.ctk"

  /// CryptoTokenKit separates the class and instance identifiers with this.
  private static let identifierSeparator = ":"

  /// Prefix shared by every ReFineID smart-card token identifier.
  public static let tokenPrefix = driverClassIdentifier + identifierSeparator

  /// The full CryptoTokenKit token identifier for one physical card.
  public static func tokenIdentifier(for instance: CardInstanceIdentifier) -> String {
    tokenPrefix + instance.value
  }

  /// Whether a full token identifier belongs to this driver.
  public static func owns(tokenIdentifier: String) -> Bool {
    tokenIdentifier.hasPrefix(tokenPrefix)
  }
}
