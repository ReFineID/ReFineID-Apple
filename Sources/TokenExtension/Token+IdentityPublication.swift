import CardCore
import CryptoTokenKit
import Foundation
import Security

/// Publishes one token's signed identity to Safari.
extension Token {
  /// Label suffix naming the PIN1 authentication identity.
  private static let authenticationRole = "tunnistautuminen (PIN1)"

  /// Label suffix naming the PIN2 qualified-signature identity.
  private static let signatureRole = "allekirjoitus (PIN2)"

  /// Appends the identity's role to the item's label.
  ///
  /// Both card certificates carry the identical subject, so every place
  /// that shows the default label - Safari's certificate chooser,
  /// Keychain Access - shows two rows that read the same. The label is
  /// the only publishable field that can tell them apart; the
  /// certificates are DVV's and cannot change.
  private static func labelRole(of item: TKTokenKeychainItem, _ role: String) {
    if let base = item.label, !base.isEmpty {
      item.label = base + " - " + role
    } else {
      item.label = role
    }
  }

  /// The qualified-signature certificate and key as keychain items.
  ///
  /// The key is sign-only and NOT suitable for login: it is the
  /// non-repudiation key, gated behind PIN2 through its own constraint,
  /// and every signature costs a fresh PIN2 entry - the session never
  /// caches one. Failure to build these is not failure to publish the
  /// token: the authentication identity stands on its own.
  private static func qualifiedItems(
    leaf: SecCertificate,
    profile: CardKeyProfile
  ) -> [TKTokenKeychainItem] {
    guard
      let certificate = TKTokenKeychainCertificate(
        certificate: leaf,
        objectID: Self.signObjectID
      ),
      let key = TKTokenKeychainKey(
        certificate: leaf,
        objectID: Self.signObjectID
      )
    else {
      TokenLog.error("publish: qualified keychain item construction failed")
      return []
    }
    key.keyType = profile.keyType
    key.keySizeInBits = profile.keySizeInBits
    key.canSign = true
    key.canDecrypt = false
    key.canPerformKeyExchange = false
    key.isSuitableForLogin = false
    // swiftlint:disable:next legacy_objc_type
    let signOperationKey = NSNumber(value: TKTokenOperation.signData.rawValue)
    key.constraints = [signOperationKey: Pin2AuthOperation.signDataConstraint]
    Self.labelRole(of: certificate, Self.signatureRole)
    Self.labelRole(of: key, Self.signatureRole)
    return [certificate, key]
  }

  /// Builds and fills the keychain contents from the read identity.
  internal func publish(
    _ identity: PublishedIdentity,
    leaf: SecCertificate,
    profile: CardKeyProfile,
    signLeaf: SecCertificate?,
    signProfile: CardKeyProfile?
  ) throws {
    guard
      let keychainCertificate = TKTokenKeychainCertificate(
        certificate: leaf,
        objectID: Self.authObjectID
      ),
      let keychainKey = TKTokenKeychainKey(
        certificate: leaf,
        objectID: Self.authObjectID
      )
    else {
      TokenLog.error("publish: keychain item construction failed")
      throw TokenError.keychainItemConstructionFailed
    }

    keychainKey.keyType = profile.keyType
    keychainKey.keySizeInBits = profile.keySizeInBits
    keychainKey.canSign = true
    keychainKey.canDecrypt = false
    keychainKey.canPerformKeyExchange = false
    keychainKey.isSuitableForLogin = true
    // The signature is gated behind PIN1: this constraint is what makes
    // CryptoTokenKit call beginAuth (the PIN sheet) before signing. Absent
    // it, the system signs without asking, our sign has no PIN, and Safari
    // fails with the identity selected but no prompt. The constraints map
    // requires NSNumber operation keys (the CryptoTokenKit ObjC API).
    // swiftlint:disable:next legacy_objc_type
    let signOperationKey = NSNumber(value: TKTokenOperation.signData.rawValue)
    keychainKey.constraints = [signOperationKey: Pin1AuthOperation.signDataConstraint]
    Self.labelRole(of: keychainCertificate, Self.authenticationRole)
    Self.labelRole(of: keychainKey, Self.authenticationRole)

    var items: [TKTokenKeychainItem] = [keychainCertificate, keychainKey]
    if let signLeaf, let signProfile {
      items.append(
        contentsOf: Self.qualifiedItems(leaf: signLeaf, profile: signProfile)
      )
    }
    if let issuerDER = identity.issuerDER,
      let issuer = SecCertificateCreateWithData(nil, issuerDER as CFData),
      let issuerItem = TKTokenKeychainCertificate(
        certificate: issuer,
        objectID: Self.issuerObjectID
      )
    {
      items.append(issuerItem)
    }
    TokenLog.info(
      "publish: filling \(items.count) items, keychainContents=\(keychainContents != nil) "
        + "publicKeyData=\(keychainKey.publicKeyData?.count ?? -1)B "
        + "publicKeyHash=\(keychainKey.publicKeyHash?.count ?? -1)B "
        + "constraints=\(keychainKey.constraints?.count ?? 0)"
    )
    keychainContents?.fill(with: items)
  }
}
