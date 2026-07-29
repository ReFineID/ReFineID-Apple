import CryptoTokenKit
import Foundation
import Security

/// Publishes one token's signed identity to Safari.
extension Token {
  /// Builds and fills the keychain contents from the read identity.
  internal func publish(
    _ identity: PublishedIdentity,
    leaf: SecCertificate,
    profile: CardKeyProfile
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

    var items: [TKTokenKeychainItem] = [keychainCertificate, keychainKey]
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
