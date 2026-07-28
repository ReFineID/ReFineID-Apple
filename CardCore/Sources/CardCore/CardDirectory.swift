import CryptoKit
import Foundation
import Security

/// Every card this device knows: serial, model, and the card access
/// number that unseals it.
///
/// The single stored number could serve one card; a household has
/// several, and a number pushed at the wrong card costs a doomed
/// handshake per offer. Entries are keyed by the token serial -- the
/// one card-unique fact, learned at the first unseal -- and carry the
/// model key so a sealed card, which is anonymous before PACE by
/// design, can at least be matched by model: the driver tries only the
/// numbers whose model matches the answer to reset, newest first.
///
/// Storage is one JSON blob: a keychain item where the app can read it
/// (and the extension too on iOS, through the shared group), and a
/// driver-configuration entry on macOS, where the extension cannot read
/// the app's keychain. The numbers are holder-visible like the single
/// stored one; nothing here enters a log.
public enum CardDirectory {
  /// One known card.
  public struct Entry: Codable, Equatable, Sendable {
    /// The card's token serial: the key, unique to the card.
    public let serial: String

    /// Hex of the ATR historical bytes: names the model, never the card.
    public let modelKey: String

    /// What to call the card on screen.
    public let model: String

    /// The six digits that unseal this card.
    public let can: String

    /// Records one card as the app learned it.
    public init(serial: String, modelKey: String, model: String, can: String) {
      self.serial = serial
      self.modelKey = modelKey
      self.model = model
      self.can = can
    }
  }

  /// Keychain coordinates; same service as the single stored number.
  private static let service = "fi.refineid.credentials"
  private static let account = "card-directory"

  /// Every known card, newest first.
  public static func entries() -> [Entry] {
    guard let data = readData() ?? driverData() else { return [] }
    return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
  }

  /// Adds or replaces the entry for `serial` at the front.
  public static func upsert(_ entry: Entry) {
    var kept = entries().filter { $0.serial != entry.serial }
    kept.insert(entry, at: 0)
    save(kept)
  }

  /// Drops the entry for `serial`.
  public static func remove(serial: String) {
    save(entries().filter { $0.serial != serial })
  }

  /// Drops every entry, here and in the driver's copy.
  public static func removeAll() {
    delete()
    #if os(macOS)
      DriverConfiguredCredentials.withdrawDirectory()
    #endif
  }

  /// The numbers worth trying against a card of `modelKey`, in stored
  /// order.
  public static func candidates(forModelKey modelKey: String) -> [CardAccessNumber] {
    entries()
      .filter { $0.modelKey == modelKey }
      .compactMap { CardAccessNumber(digits: $0.can) }
  }

  /// An opaque digest over the candidate set for `modelKey`: equal when
  /// the set is, never convertible back.
  ///
  /// The driver latches a refusal against it, so editing the directory
  /// is what earns a card a fresh attempt.
  public static func candidatesFingerprint(forModelKey modelKey: String) -> Data? {
    let matching = entries().filter { $0.modelKey == modelKey }
    guard !matching.isEmpty else { return nil }
    let material = matching.map { $0.serial + ":" + $0.can }.joined(separator: "\n")
    return Data(SHA256.hash(data: Data(material.utf8)))
  }

  /// Writes the whole directory and mirrors it to the driver on macOS.
  private static func save(_ entries: [Entry]) {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    if entries.isEmpty {
      delete()
    } else {
      write(data)
    }
    #if os(macOS)
      if entries.isEmpty {
        DriverConfiguredCredentials.withdrawDirectory()
      } else {
        DriverConfiguredCredentials.publishDirectory(data)
      }
    #endif
  }

  /// The driver-side copy, for the process that cannot read the
  /// keychain item.
  private static func driverData() -> Data? {
    #if os(macOS)
      DriverConfiguredCredentials.directoryData()
    #else
      nil
    #endif
  }

  /// Item coordinates shared by the three keychain operations.
  private static func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private static func readData() -> Data? {
    var query = self.query()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
    return item as? Data
  }

  private static func write(_ data: Data) {
    let attributes: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query() as CFDictionary, attributes as CFDictionary)
    guard status == errSecItemNotFound else { return }
    var add = query()
    add[kSecValueData as String] = data
    SecItemAdd(add as CFDictionary, nil)
  }

  private static func delete() {
    SecItemDelete(query() as CFDictionary)
  }
}
