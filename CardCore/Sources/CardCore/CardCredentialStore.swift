import Foundation
import Security

/// Where this device keeps the card access number, and optionally PIN1.
///
/// Both are held as keychain items whose protection class is
/// `WhenUnlockedThisDeviceOnly` and which are explicitly
/// non-synchronizable, so they never enter a backup, never restore onto
/// another device, and never reach iCloud. The keys that encrypt them are
/// derived inside the Secure Enclave; secrets themselves cannot live in
/// the enclave, which holds only keys, so this protection class is what
/// "enclave-backed" actually means for a stored value.
///
/// Biometry deliberately does NOT gate these items. The token extension
/// reads them while signing a request the holder made in Safari, with no
/// interface of its own to present a Face ID prompt, so a biometric
/// access control here would stall every system-driven login on a prompt
/// nobody can answer. The gate belongs where a person is present: the app
/// authenticates before it will show, change, or clear anything, which is
/// what ``CardCredentialGate`` is for.
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

  /// The stored card access number, or nil.
  public static func cardAccessNumber() -> CardAccessNumber? {
    read(account: cardAccessNumberAccount).flatMap(CardAccessNumber.init(digits:))
  }

  /// The stored PIN1, or nil when the holder never opted in.
  public static func pin1() -> Pin1? {
    read(account: pin1Account).flatMap(Pin1.init(digits:))
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
  /// `ThisDeviceOnly` is what keeps these out of backups and off other
  /// devices; `synchronizable` false is what keeps them out of iCloud.
  /// Both are required -- neither implies the other.
  private static func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private static func exists(account: String) -> Bool {
    var query = self.query(account: account)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
  }

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

  private static func write(_ digits: String, account: String) -> Bool {
    guard let data = digits.data(using: .utf8) else { return false }
    delete(account: account)
    var attributes = query(account: account)
    attributes[kSecValueData as String] = data
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  private static func delete(account: String) {
    SecItemDelete(query(account: account) as CFDictionary)
  }
}
