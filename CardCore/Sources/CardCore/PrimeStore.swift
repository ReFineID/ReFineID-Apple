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
  /// A contactless lookup result and the field purpose it represents.
  public struct ContactlessMatch: Sendable {
    /// The identity metadata to publish.
    public let identity: PrimedIdentity

    /// True only for the app's one-time registration field.
    ///
    /// The token extension must publish without taking a card session in
    /// this field. Later signing fields take and retain the session.
    public let isRegistrationField: Bool
  }

  /// One decoded keychain record, still named only inside this store.
  private struct StoredItem {
    let account: String
    let identity: PrimedIdentity
  }

  /// Keychain service the primed identities live under.
  private static let service: String = "fi.refineid.prime"

  /// Short-lived bridge from the Core NFC read to the next CTK field.
  private static let stagedAccount = "staged-contactless-card"

  /// A staged record exists only to bridge two consecutive NFC fields.
  private static let maximumStagedAge: TimeInterval = 90

  /// Tolerates a small wall-clock adjustment between app and extension.
  private static let allowedFutureSkew: TimeInterval = 5

  /// Stores the primed identity for one card, replacing any previous one.
  ///
  /// Returns false when the keychain refuses the write, so a caller can
  /// tell the holder that priming did not stick rather than leaving them
  /// to discover it at the next login.
  @discardableResult
  public static func store(
    _ identity: PrimedIdentity,
    forLookup lookupID: PrimeLookupIdentifier
  ) -> Bool {
    guard let payload = try? JSONEncoder().encode(identity) else { return false }
    var attributes = query(account: lookupID.value)
    attributes[kSecValueData as String] = payload
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    forget(lookupID: lookupID)
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  /// Stages a freshly read Core NFC identity for the next CTK field.
  ///
  /// The extension accepts it only while fresh and only when its
  /// identification bytes occur inside the live CTK ATR. Those bytes
  /// identify a compatible card family, not one physical card; the setup
  /// screen therefore requires the holder to keep the same card in place.
  @discardableResult
  public static func stage(
    _ identity: PrimedIdentity,
    contactlessIdentification: Data
  ) -> Bool {
    guard
      let staged = PrimedIdentity(
        can: identity.can,
        certificate: identity.certDER,
        issuer: identity.issuerDER,
        tokenSerial: identity.tokenSerial,
        contactlessIdentification: contactlessIdentification,
        stagedAt: Date()),
      let payload = try? JSONEncoder().encode(staged)
    else {
      return false
    }
    var attributes = query(account: Self.stagedAccount)
    attributes[kSecValueData as String] = payload
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    delete(account: Self.stagedAccount)
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  /// The primed identity for one card, or nil when there is none.
  ///
  /// A stored record is re-validated through `PrimedIdentity`'s own
  /// initializer instead of being trusted: decoding proves the bytes are
  /// well-formed JSON, not that they still describe a usable prime.
  public static func read(lookupID: PrimeLookupIdentifier) -> PrimedIdentity? {
    read(account: lookupID.value)
  }

  /// Reads the staged registration record first, then the exact ATR record.
  ///
  /// Staged must win even when an old exact record exists. Otherwise a
  /// re-prime looks like a signing field, and the extension starts PACE
  /// while the app is trying to register the token.
  public static func readContactless(
    lookupID: PrimeLookupIdentifier,
    answerToReset: Data
  ) -> ContactlessMatch? {
    if let staged = read(account: Self.stagedAccount),
      let stagedAt = staged.stagedAt,
      let identification = staged.contactlessIdentification
    {
      let age = Date().timeIntervalSince(stagedAt)
      if age >= -Self.allowedFutureSkew,
        age <= Self.maximumStagedAge,
        answerToReset.contains(identification)
      {
        return ContactlessMatch(identity: staged, isRegistrationField: true)
      }
    }
    guard let exact = read(lookupID: lookupID) else { return nil }
    return ContactlessMatch(identity: exact, isRegistrationField: false)
  }

  /// Decodes and validates one record by keychain account.
  private static func read(account: String) -> PrimedIdentity? {
    var query = self.query(account: account)
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
      tokenSerial: stored.tokenSerial,
      contactlessIdentification: stored.contactlessIdentification,
      stagedAt: stored.stagedAt)
  }

  /// Removes the primed identity for one card.
  public static func forget(lookupID: PrimeLookupIdentifier) {
    delete(account: lookupID.value)
  }

  /// Whether a stored prime belongs to this physical card.
  ///
  /// The lookup key is derived from an ATR and therefore names a card
  /// family, not a physical card. Revocation starts with the public card
  /// serial instead, so it cannot remove another card's prime merely
  /// because both cards expose the same ATR.
  public static func contains(instanceID: CardInstanceIdentifier) -> Bool {
    storedItems().contains { item in
      guard
        let serialText = item.identity.tokenSerial,
        let serial = TokenSerial(value: serialText)
      else {
        return false
      }
      return CardInstanceIdentifier(tokenSerial: serial) == instanceID
    }
  }

  /// Removes every exact or staged prime belonging to one physical card.
  ///
  /// A physical card can acquire more than one ATR lookup record across
  /// interfaces or card generations. The printed-card instance identifier
  /// is the stable revocation boundary, so all matching records go together.
  public static func forget(instanceID: CardInstanceIdentifier) {
    for item in storedItems() {
      guard
        let serialText = item.identity.tokenSerial,
        let serial = TokenSerial(value: serialText),
        CardInstanceIdentifier(tokenSerial: serial) == instanceID
      else {
        continue
      }
      delete(account: item.account)
    }
  }

  /// Removes the short-lived bridge record after registration.
  public static func forgetStaged() {
    delete(account: Self.stagedAccount)
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
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
    SecItemDelete(query as CFDictionary)
  }

  /// How many cards this device currently holds a prime for.
  ///
  /// A count and nothing else. The record names one card and carries its
  /// card access number, so a caller that only needs to know whether
  /// priming stuck gets a number rather than something to leak. Zero is
  /// also the answer when the keychain refuses the search, which reads the
  /// same way to a caller: there is no prime here to serve a login with.
  public static func storedCount() -> Int {
    presence().count
  }

  /// What this device holds for each primed card, presence only.
  ///
  /// ``storedCount()`` answers whether priming stuck at all; this answers
  /// which part of it stuck, which is the difference between a card that
  /// was never read and one whose issuer certificate never arrived. The
  /// records are decoded here, inside the type that owns them, and only
  /// presence and sizes leave: no card access number, no certificate
  /// bytes, no serial. An unreadable or undecodable record is skipped
  /// rather than reported as an empty one, because a prime that cannot be
  /// decoded is a prime the extension will not see either.
  public static func presence() -> [PrimePresence] {
    storedItems()
      .filter { $0.account != Self.stagedAccount }
      .map { item in
        PrimePresence(
          instance: item.account,
          hasCardAccessNumber: !item.identity.can.isEmpty,
          certificateBytes: item.identity.certDER.count,
          issuerBytes: item.identity.issuerDER?.count ?? 0,
          hasTokenSerial: item.identity.tokenSerial != nil)
      }
      .sorted { $0.instance < $1.instance }
  }

  /// Every decodable prime, including the short-lived staged record.
  private static func storedItems() -> [StoredItem] {
    var search: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
    search[kSecMatchLimit as String] = kSecMatchLimitAll
    search[kSecReturnAttributes as String] = true
    search[kSecReturnData as String] = true
    var items: CFTypeRef?
    guard SecItemCopyMatching(search as CFDictionary, &items) == errSecSuccess,
      let found = items as? [[String: Any]]
    else {
      return []
    }
    return found.compactMap { attributes in
      guard
        let account = attributes[kSecAttrAccount as String] as? String,
        let data = attributes[kSecValueData as String] as? Data,
        let identity = try? JSONDecoder().decode(PrimedIdentity.self, from: data)
      else {
        return nil
      }
      return StoredItem(account: account, identity: identity)
    }
  }

  /// Item coordinates shared by every operation on one card's prime.
  ///
  /// The accessibility attribute is deliberately absent here: it belongs
  /// on the write, and a search that filters on it would miss items
  /// written under any other policy instead of replacing them.
  private static func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
  }

  /// Removes one account without exposing its coordinates to callers.
  private static func delete(account: String) {
    SecItemDelete(query(account: account) as CFDictionary)
  }
}
