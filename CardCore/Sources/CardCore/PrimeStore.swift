import Foundation
import Security

/// Where a primed identity waits between the app that read it and the
/// token extension that needs it.
///
/// The two are separate processes, and `ctkd` purges the app-side
/// `TKTokenDriver.Configuration` entries for a smart-card driver class the
/// moment the driver creates a token -- so the obvious channel deletes
/// itself exactly when it would be used. A keychain item in the shared
/// access group is the one store both sides genuinely share, and it is
/// where a card access number belongs anyway.
///
/// Items are `WhenUnlockedThisDeviceOnly` and non-synchronizable: a prime
/// is only ever read while the holder is standing over an unlocked device
/// driving a login, so nothing here needs to survive a lock, a backup, or
/// a restore onto another device. Neither attribute implies the other;
/// both are set. `kSecUseDataProtectionKeychain` must be set identically
/// on both sides or the app and the extension address different keychains
/// and silently never see each other's writes.
///
/// Nothing in this type logs. The value it carries includes a card access
/// number, and a store that narrates its work is a store that eventually
/// narrates that.
///
/// Provenance: the reader `PrimeStore` in the donor
/// `platform/apple/RefineIDTokenExtension/PrimeStore.swift` and the writer
/// `SafariIdentityPrime.storePrimedIdentity` in
/// `platform/apple/RefineID/Local/SafariIdentityPrime+PrimeStore.swift`.
public enum PrimeStore {
  /// Keychain service the primed identities live under.
  private static let service: String = "fi.refineid.prime"

  /// Stores the primed identity for one card, replacing any previous one.
  ///
  /// Returns false when the keychain refuses the write, so a caller can
  /// tell the holder that priming did not stick rather than leaving them
  /// to discover it at the next login.
  @discardableResult
  public static func store(
    _ identity: PrimedIdentity,
    forInstance instanceID: CardInstanceIdentifier
  ) -> Bool {
    guard let payload = try? JSONEncoder().encode(identity) else { return false }
    var attributes = query(instanceID: instanceID)
    attributes[kSecValueData as String] = payload
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    forget(instanceID: instanceID)
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  /// The primed identity for one card, or nil when there is none.
  ///
  /// A stored record is re-validated through `PrimedIdentity`'s own
  /// initializer instead of being trusted: decoding proves the bytes are
  /// well-formed JSON, not that they still describe a usable prime.
  public static func read(instanceID: CardInstanceIdentifier) -> PrimedIdentity? {
    var query = self.query(instanceID: instanceID)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let stored = try? JSONDecoder().decode(PrimedIdentity.self, from: data)
    else {
      return nil
    }
    return PrimedIdentity(
      can: stored.can,
      certificate: stored.certDER,
      issuer: stored.issuerDER,
      tokenSerial: stored.tokenSerial)
  }

  /// Removes the primed identity for one card.
  public static func forget(instanceID: CardInstanceIdentifier) {
    SecItemDelete(query(instanceID: instanceID) as CFDictionary)
  }

  /// Removes every primed identity this device holds.
  ///
  /// The holder revoking their consent to a stored card access number
  /// must be able to revoke it for all their cards at once, without
  /// having to present each card again to name it.
  public static func forgetAll() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
    ]
    SecItemDelete(query as CFDictionary)
  }

  /// Item coordinates shared by every operation on one card's prime.
  ///
  /// The accessibility attribute is deliberately absent here: it belongs
  /// on the write, and a search that filters on it would miss items
  /// written under any other policy instead of replacing them.
  private static func query(instanceID: CardInstanceIdentifier) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: instanceID.value,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
    ]
  }
}
