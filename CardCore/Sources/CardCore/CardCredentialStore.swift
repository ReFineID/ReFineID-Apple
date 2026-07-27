import Foundation
import Security

/// Where this device keeps the card access number, and optionally PIN1.
///
/// Neither value is ever handed back for display: they are written once,
/// and afterwards the store will only say whether something is present.
/// Both are `WhenUnlockedThisDeviceOnly` and non-synchronizable, so
/// neither is written into a backup, restored onto another device, or
/// sent to iCloud. Neither attribute implies the other; both are set.
///
/// The two differ in how they are read back, because they are not
/// equally secret.
///
/// **PIN1 is protected as strongly as the platform allows.** Its item
/// carries a `SecAccessControl`, so a read fails inside the Security
/// framework unless the holder authenticates at that moment -- policy
/// checked in app code would be bypassable by anything that can call
/// this type, an access control is not. The policy is
/// `.biometryCurrentSet` rather than `.userPresence`, so knowing the
/// device passcode is not enough, and enrolling a new face or finger
/// invalidates it instead of silently extending access to whoever
/// enrolled it. The cost is stated in the interface: change your
/// biometrics and PIN1 must be entered again.
///
/// **The card access number is protected, but not gated.** It is printed
/// on the front of the card, so a biometric prompt in front of it would
/// buy very little and would cost a prompt every time a card is set up.
/// It is still never displayed, never backed up, never synced -- it is
/// simply readable by this app and its token extension without asking.
/// That is a deliberate trade for a semi-public value, recorded here so
/// it reads as a decision rather than an oversight.
///
/// Secrets cannot live *inside* the Secure Enclave, which holds only
/// keys. What the enclave provides is the key material these items are
/// encrypted under, and the biometric evaluation gating PIN1.
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
  public static func save(cardAccessNumber digits: String) -> Bool {
    guard CardAccessNumber(digits: digits) != nil else { return false }
    return write(digits, account: cardAccessNumberAccount, gated: false)
  }

  /// Stores PIN1 for unattended signing, replacing any previous one.
  ///
  /// Storing PIN1 trades the rule that one signature costs one PIN entry:
  /// anything that can reach the token can then sign without the holder
  /// present. Offer it as a choice, never as a default, and say so where
  /// the choice is made.
  @discardableResult
  public static func save(pin1 digits: String) -> Bool {
    guard Pin1(digits: digits) != nil else { return false }
    return write(digits, account: pin1Account, gated: true)
  }

  /// The stored card access number.
  ///
  /// Reads without prompting: the number is printed on the card, and a
  /// prompt in front of it would cost the holder an interruption on
  /// every card setup for very little.
  public static func cardAccessNumber() -> CardAccessNumber? {
    read(account: cardAccessNumberAccount, reason: nil)
      .flatMap(CardAccessNumber.init(digits:))
  }

  /// The stored PIN1, after the holder authenticates, or nil when they
  /// never opted in.
  public static func pin1(reason: String) -> Pin1? {
    read(account: pin1Account, reason: reason).flatMap(Pin1.init(digits:))
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
    guard let digits = read(account: cardAccessNumberAccount, reason: nil) else {
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
  /// master copy is gated, so `reason` is shown to the holder; the window
  /// it opens is not, and closes itself after fifteen idle minutes.
  ///
  /// The digits never leave this type: they are read, handed to
  /// ``Pin1SigningWindow``, and dropped. Returns false when no PIN1 is
  /// stored, the holder did not authenticate, or the window could not be
  /// written.
  public static func openSigningWindow(reason: String) -> Bool {
    guard let digits = read(account: pin1Account, reason: reason) else { return false }
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
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
    ]
  }

  /// The access control PIN1 carries.
  ///
  /// Returns nil only when the platform refuses to build it, in which
  /// case PIN1 is not stored at all: writing it without its access
  /// control would leave it readable without authentication, which is
  /// the one thing this must never do.
  private static func pin1AccessControl() -> SecAccessControl? {
    SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      .biometryCurrentSet,
      nil)
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
  /// A `reason` is shown in the biometric prompt for items that carry an
  /// access control; passing nil reads an ungated item without asking.
  /// Nothing in the app calls this to display a value -- it exists so
  /// card setup can use what was entered earlier.
  private static func read(account: String, reason: String?) -> String? {
    var query = self.query(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    if let reason {
      query[kSecUseOperationPrompt as String] = reason
    }
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Writes a value, biometrically gated only when `gated` is set.
  private static func write(_ digits: String, account: String, gated: Bool) -> Bool {
    guard let data = digits.data(using: .utf8) else { return false }
    var attributes = query(account: account)
    attributes[kSecValueData as String] = data
    if gated {
      guard let control = pin1AccessControl() else { return false }
      attributes[kSecAttrAccessControl as String] = control
    } else {
      attributes[kSecAttrAccessible as String] =
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    delete(account: account)
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  /// Removes an item.
  ///
  /// Deletion never needs the value, so it never prompts.
  private static func delete(account: String) {
    var query = self.query(account: account)
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    SecItemDelete(query as CFDictionary)
  }
}
