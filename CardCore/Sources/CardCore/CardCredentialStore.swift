import Foundation
import Security

/// Where this device keeps the card access number, and optionally PIN1.
///
/// Neither value is ever handed back for display: they are written once,
/// and afterwards the store will only say whether something is present.
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
/// `CardCredentialGate`, in front of every path that stores or drops one
/// of these values. That is weaker than an access control -- app code can
/// be talked past, the Security framework cannot -- and it is a deliberate
/// trade, recorded in `Documentation/decisions.md` rather than left to be
/// discovered here.
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

  /// What is stored, without reading any secret.
  public static func contents() -> Contents {
    Contents(
      hasCardAccessNumber: exists(account: cardAccessNumberAccount),
      hasPin1: exists(account: pin1Account))
  }

  /// Stores the card access number, replacing any previous one.
  @discardableResult
  public static func save(cardAccessNumber digits: String) -> OSStatus {
    guard CardAccessNumber(digits: digits) != nil else { return errSecParam }
    return write(digits, account: cardAccessNumberAccount)
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
    read(account: cardAccessNumberAccount)
      .flatMap(CardAccessNumber.init(digits:))
  }

  /// The stored PIN1, or nil when the holder never entered one.
  public static func pin1() -> Pin1? {
    read(account: pin1Account).flatMap(Pin1.init(digits:))
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

  /// Opens the fifteen-minute signing window from the stored PIN1.
  ///
  /// The window is how the first PIN reaches the token extension, which
  /// has no interface to ask for one with while Safari waits. Reading the
  /// window
  /// it opens is not, and closes itself after fifteen idle minutes.
  ///
  /// The digits never leave this type: they are read, handed to
  /// ``Pin1SigningWindow``, and dropped. Returns false when no PIN1 is
  /// stored, the holder did not authenticate, or the window could not be
  /// written.
  public static func openSigningWindow() -> Bool {
    guard let digits = read(account: pin1Account) else { return false }
    return Pin1SigningWindow.open(pin1: digits)
  }

  /// Removes the card access number.
  public static func forgetCardAccessNumber() {
    delete(account: cardAccessNumberAccount)
  }

  /// Removes PIN1, returning to a prompt for every signature.
  public static func forgetPin1() {
    delete(account: pin1Account)
  }

  /// Removes everything this device knows about the card's secrets.
  public static func forgetAll() {
    delete(account: cardAccessNumberAccount)
    delete(account: pin1Account)
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
