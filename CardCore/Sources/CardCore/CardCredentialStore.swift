import CryptoKit
import Foundation
import Security

/// Where this device keeps the card access number, and optionally PIN1.
///
/// PIN1 is never handed back for display: written once, present-or-absent
/// afterwards. The card access number is the holder's to see -- it is
/// printed on the card face -- and ``displayedCardAccessNumber()`` returns
/// it for the manager window. Neither enters a log.
///
/// Both are `WhenUnlockedThisDeviceOnly` and non-synchronizable, so
/// neither is written into a backup, restored onto another device, or
/// sent to iCloud. Neither attribute implies the other; both are set.
///
/// Neither item carries a `SecAccessControl`. PIN1 did, briefly, and it
/// is worth recording why it does not now: the token extension has to
/// read PIN1 while signing a request made in Safari and has no interface
/// to answer a prompt with, so an item-level gate cannot serve the flow
/// this app exists for. It also broke storage outright -- a protected
/// item survives a delete that skips the authentication interface, and
/// the add that follows fails as a duplicate, so a perfectly good PIN
/// looked rejected.
///
/// The biometric gate therefore lives one layer up, in the app's
/// `CardCredentialGate`, in front of every path that stores or drops
/// PIN1. That is weaker than an access control -- app code can be talked
/// past, the Security framework cannot -- and it is a deliberate trade,
/// recorded in `Documentation/decisions.md` rather than left to be
/// discovered here. The card access number passes no gate in either
/// direction.
public enum CardCredentialStore {
  /// What the store currently holds.
  public struct Contents: Equatable, Sendable {
    /// Whether a card access number is stored.
    public let hasCardAccessNumber: Bool

    /// Whether PIN1 is stored for unattended signing.
    public let hasPin1: Bool

    /// Records what a store lookup found.
    public init(hasCardAccessNumber: Bool, hasPin1: Bool) {
      self.hasCardAccessNumber = hasCardAccessNumber
      self.hasPin1 = hasPin1
    }
  }

  /// Keychain service the card credentials live under.
  private static let service = "fi.refineid.credentials"

  /// Account for the card access number.
  private static let cardAccessNumberAccount = "can"

  /// Account for PIN1, present only when the holder opted in.
  private static let pin1Account = "pin1"

  /// Keychain coordinates used by the retired timed signing window.
  private static let legacySigningWindowService = "fi.refineid.pin1window"
  private static let legacySigningWindowAccount = "current"

  /// What is stored, without reading any secret.
  public static func contents() -> Contents {
    Contents(
      hasCardAccessNumber: exists(account: cardAccessNumberAccount),
      hasPin1: exists(account: pin1Account))
  }

  /// Stores the card access number, replacing any previous one.
  ///
  /// Also hands it to the token driver, which on macOS cannot read the
  /// keychain item this just wrote. See `publishCardAccessNumberToDriver`.
  @discardableResult
  public static func save(cardAccessNumber digits: String) -> OSStatus {
    guard CardAccessNumber(digits: digits) != nil else { return errSecParam }
    let status = write(digits, account: cardAccessNumberAccount)
    if status == errSecSuccess {
      publishToDriver(digits: digits)
    }
    return status
  }

  /// An opaque name for the stored number: equal when the number is,
  /// never convertible back to digits.
  ///
  /// Lets the token driver remember "this exact number was refused by
  /// this card" across offers without holding digits, which is what
  /// stops a wrong number from being retried against the card for as
  /// long as it rests on the antenna.
  public static func cardAccessNumberFingerprint() -> Data? {
    var digits = read(account: cardAccessNumberAccount).map { Data($0.utf8) }
    #if os(macOS)
      if digits == nil {
        digits = DriverConfiguredCredentials.digitsData()
      }
    #endif
    guard let digits else { return nil }
    return Data(SHA256.hash(data: digits))
  }

  /// Hands the stored card access number to the token driver, for the
  /// platform where it cannot read the keychain item itself.
  ///
  /// Called by the app when it starts, not only when the number is
  /// entered: a number stored before this channel existed, or by a
  /// previous version, would otherwise stay invisible to the driver
  /// until the holder happened to type it again.
  ///
  /// Answers whether anything was published, so a caller can say so.
  /// False covers both nothing stored and a process that is not the
  /// driver's hosting application, neither of which is an error.
  @discardableResult
  public static func publishCardAccessNumberToDriver() -> Bool {
    guard let digits = read(account: cardAccessNumberAccount) else { return false }
    return publishToDriver(digits: digits)
  }

  /// The platform half of the above: iOS shares a keychain access group
  /// with its extensions and needs no second copy of the number, so it
  /// does not make one.
  @discardableResult
  private static func publishToDriver(digits: String) -> Bool {
    #if os(macOS)
      return DriverConfiguredCredentials.publish(digits: digits)
    #else
      return false
    #endif
  }

  /// The stored card access number, for the holder to see.
  ///
  /// The number is printed on the card face; hiding it from its holder
  /// protected nothing and cost the manager window its one job. PIN1
  /// has no counterpart to this, and the value still never reaches a
  /// log, a trace or a diagnostics export.
  public static func displayedCardAccessNumber() -> String? {
    read(account: cardAccessNumberAccount)
  }

  /// Stores PIN1 for unattended signing, replacing any previous one.
  ///
  /// Storing PIN1 trades the rule that one signature costs one PIN entry:
  /// anything that can reach the token can then sign without the holder
  /// present. Offer it as a choice, never as a default, and say so where
  /// the choice is made.
  @discardableResult
  public static func save(pin1 digits: String) -> OSStatus {
    guard Pin1(digits: digits) != nil else { return errSecParam }
    return write(digits, account: pin1Account)
  }

  /// The stored card access number.
  ///
  /// Reads without prompting: the number is printed on the card, and a
  /// prompt in front of it would cost the holder an interruption on
  /// every card setup for very little.
  public static func cardAccessNumber() -> CardAccessNumber? {
    if let stored = read(account: cardAccessNumberAccount)
      .flatMap(CardAccessNumber.init(digits:))
    {
      return stored
    }
    // The token driver's own copy, which on macOS is the only one it can
    // read. Second rather than first, so the keychain stays the source of
    // truth wherever it is readable.
    #if os(macOS)
      return DriverConfiguredCredentials.cardAccessNumber()
    #else
      return nil
    #endif
  }

  /// The keychain's own answer to "could the card access number be read
  /// from this process?", for when it could not.
  ///
  /// `cardAccessNumber()` answers nil for every reason there is, and the
  /// reasons want different things done about them: `errSecItemNotFound`
  /// is setup that has not happened, while a refusal is one process
  /// being unable to read what another one wrote. A caller that has
  /// already failed can say which it hit instead of guessing.
  /// Asks for the value, not merely the item: on macOS the two are
  /// different questions, because finding an item needs no authorization
  /// while reading its data is what the access control governs. A probe
  /// that omitted the data reported success for an item it could not
  /// actually read.
  public static func cardAccessNumberReadStatus() -> OSStatus {
    var query = self.query(account: cardAccessNumberAccount)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &item)
  }

  /// The stored PIN1, or nil when the holder never entered one.
  public static func pin1() -> Pin1? {
    read(account: pin1Account).flatMap(Pin1.init(digits:))
  }

  /// Removes the duplicate PIN item written by builds with a timed
  /// signing window.
  ///
  /// Current builds sign directly from the holder's explicitly stored
  /// credential, so the derived copy has no reader and must not survive
  /// an upgrade indefinitely.
  public static func removeLegacySigningWindow() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: legacySigningWindowService,
      kSecAttrAccount as String: legacySigningWindowAccount,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
    SecItemDelete(query as CFDictionary)
  }

  /// The primed identity for a card that was just read, built around the
  /// stored card access number.
  ///
  /// The prime store needs the six digits, and this type is where they
  /// live. Handing them out so a caller could assemble the record itself
  /// would put a card access number in a `String` in the app, in the
  /// extension, and in every caller added later; assembling the record
  /// here means the digits go from the keychain into the prime without
  /// passing through any other file. Returns nil when nothing is stored
  /// or the record would not validate.
  public static func primedIdentity(
    certificate: Data,
    issuer: Data?,
    tokenSerial: String?
  ) -> PrimedIdentity? {
    guard let digits = read(account: cardAccessNumberAccount) else {
      return nil
    }
    return PrimedIdentity(
      can: digits,
      certificate: certificate,
      issuer: issuer,
      tokenSerial: tokenSerial)
  }

  /// Removes the card access number, from the driver's copy as well.
  public static func forgetCardAccessNumber() {
    delete(account: cardAccessNumberAccount)
    #if os(macOS)
      DriverConfiguredCredentials.withdraw()
    #endif
  }

  /// Removes PIN1, returning to a prompt for every signature.
  public static func forgetPin1() {
    delete(account: pin1Account)
  }

  /// Removes everything this device knows about the card's secrets.
  public static func forgetAll() {
    delete(account: cardAccessNumberAccount)
    delete(account: pin1Account)
    CardDirectory.removeAll()
    #if os(macOS)
      DriverConfiguredCredentials.withdraw()
    #endif
  }

  /// Item coordinates shared by every operation.
  ///
  /// `ThisDeviceOnly` keeps these out of backups and off other devices;
  /// `synchronizable` false keeps them out of iCloud. Both are required
  /// -- neither implies the other.
  private static func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      // iOS only. On macOS the data-protection keychain requires a
      // keychain-access-group entitlement, and asking for one there
      // fails signing on a development profile -- every store call then
      // answers errSecMissingEntitlement and the app cannot keep a card
      // access number at all. The file keychain needs no entitlement and
      // is protected by the same login keychain the rest of the system
      // uses.
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
  }

  /// Whether an item is present, without authenticating.
  ///
  /// The lookup explicitly skips any interface. A protected item then
  /// answers `errSecInteractionNotAllowed`, which is itself proof that
  /// it exists -- so both that and success count as present, and neither
  /// prompts the holder just to draw a status row.
  private static func exists(account: String) -> Bool {
    var query = self.query(account: account)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }

  /// Reads a value.
  ///
  /// Nothing in the app calls this to display a value -- it exists so
  /// card setup can use what was entered earlier.
  private static func read(account: String) -> String? {
    var query = self.query(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Writes a value.
  ///
  /// Returns the keychain's own status rather than a bare false, because
  /// a refusal here is not the holder's fault, and telling them their PIN
  /// is invalid when the store merely could not replace an item sends
  /// them looking in the wrong place.
  private static func write(_ digits: String, account: String) -> OSStatus {
    guard let data = digits.data(using: .utf8) else { return errSecParam }
    var attributes = query(account: account)
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] =
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    delete(account: account)
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecDuplicateItem else { return status }
    // The old item outlived the delete, which a protected item can do.
    // Replacing its data in place still gets the holder what they asked
    // for, and it keeps the access control that is already on it.
    return SecItemUpdate(
      query(account: account) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary)
  }

  /// Removes an item.
  ///
  /// Deletion does NOT skip the authentication interface. Skipping it
  /// makes a biometrically protected item answer
  /// `errSecInteractionNotAllowed` and survive, after which the add that
  /// follows fails as a duplicate and a perfectly good PIN looks
  /// rejected. Measured: this is exactly why storing PIN1 appeared to do
  /// nothing while storing the ungated access number worked.
  private static func delete(account: String) {
    SecItemDelete(query(account: account) as CFDictionary)
  }
}
