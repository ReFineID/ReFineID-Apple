import Foundation
import Security

/// Where this device keeps the card access number, and optionally PIN1.
///
/// These values are written once and never handed back for display. The
/// store is deliberately shaped so that no combination of backup,
/// sync, or code running as this app can produce them again:
///
/// - **Biometry is enforced by the item, not by this app.** Each item
///   carries a `SecAccessControl` requiring the current biometric set,
///   so a read fails in the Security framework itself unless the holder
///   authenticates at that moment. Policy checked in app code would be
///   bypassable by anything that can call this type; an access control
///   is not.
/// - **`.biometryCurrentSet` rather than `.userPresence`,** so knowing
///   the device passcode is not enough, and enrolling a new face or
///   finger invalidates the items rather than silently extending access
///   to whoever enrolled it. The cost is honest: change your biometrics
///   and these values must be entered again.
/// - **`WhenUnlockedThisDeviceOnly`,** so they are never written into a
///   backup and never restore onto another device.
/// - **`synchronizable` false,** so they never reach iCloud. Neither
///   attribute implies the other; both are required.
///
/// Secrets cannot live *inside* the Secure Enclave, which holds only
/// keys. What the enclave provides here is the key material these items
/// are encrypted under and the biometric evaluation that gates them,
/// which is what "enclave-backed storage" means for a stored value.
///
/// The token extension does not read this store. It signs from the
/// primed identity written during card setup, so nothing here has to be
/// readable while the holder is absent.
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
    return write(digits, account: cardAccessNumberAccount)
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
    return write(digits, account: pin1Account)
  }

  /// The stored card access number, after the holder authenticates.
  ///
  /// `reason` is shown in the system's biometric prompt, so it should
  /// say what the value is about to be used for.
  public static func cardAccessNumber(reason: String) -> CardAccessNumber? {
    read(account: cardAccessNumberAccount, reason: reason)
      .flatMap(CardAccessNumber.init(digits:))
  }

  /// The stored PIN1, after the holder authenticates, or nil when they
  /// never opted in.
  public static func pin1(reason: String) -> Pin1? {
    read(account: pin1Account, reason: reason).flatMap(Pin1.init(digits:))
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

  /// The access control every stored value carries.
  ///
  /// Returns nil only when the platform refuses to build it, in which
  /// case nothing is stored: a value written without its access control
  /// would be readable without authentication, which is exactly what
  /// this store exists to prevent.
  private static func accessControl() -> SecAccessControl? {
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

  /// Reads a value, which prompts the holder for biometrics.
  ///
  /// Nothing in the app calls this to show a value; it exists so the
  /// card setup flow can use what was entered earlier.
  private static func read(account: String, reason: String) -> String? {
    var query = self.query(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseOperationPrompt as String] = reason
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private static func write(_ digits: String, account: String) -> Bool {
    guard let data = digits.data(using: .utf8), let control = accessControl() else {
      return false
    }
    delete(account: account)
    var attributes = query(account: account)
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessControl as String] = control
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
