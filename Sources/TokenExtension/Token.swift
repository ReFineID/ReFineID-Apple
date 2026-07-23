import CardCore
import CryptoKit
import CryptoTokenKit
import Foundation
import Security

/// The token instance for one inserted card.
///
/// At creation it reads the on-card authentication certificate through
/// CardCore, discovers the key profile, and publishes into the keychain
/// the leaf certificate, a sign-only key gated behind PIN1, and (when
/// present) the issuing-CA certificate - so Safari offers the identity
/// at a service's client-certificate request. Signing itself is the
/// session's responsibility.
internal final class Token: TKSmartCardToken, TKTokenDelegate {
  /// The auth certificate and its key share this keychain object ID.
  private static let authObjectID = "auth"

  /// The published issuing-CA certificate's object ID (cert-only).
  private static let issuerObjectID = "issuer-ca"

  /// Schema version of what this token publishes.
  ///
  /// ctkd caches keychain contents by instanceID; folding this in means
  /// a change to the published set yields a new instanceID and a
  /// rebuild. Bump on any change to the published contents.
  /// v2 = the signing key carries the PIN1 signData constraint.
  private static let contentsVersion = "2"

  /// Hex characters of the leaf fingerprint kept in the instance ID -
  /// enough to identify the card without an oversized identifier.
  private static let instanceFingerprintLength = 16

  /// The authentication key's profile, resolved from the leaf and used
  /// by the session to advertise and select signing algorithms.
  internal let keyProfile: CardKeyProfile

  /// The leaf's public key, used by the session to verify each raw card
  /// signature before returning it - a card that lost its loaded hash
  /// signs silently-wrong bytes with no error SW (S1 v4.2 §3.8.1.1), and
  /// the token must fail closed rather than feed the TLS stack garbage.
  internal let leafPublicKey: SecKey

  internal init(
    smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver
  ) throws {
    TokenLog.info("Token.init: reading identity")
    let identity = try Self.readIdentity(from: smartCard)
    TokenLog.info(
      "Token.init: leaf=\(identity.leafDER.count) issuer=\(identity.issuerDER?.count ?? -1)"
    )
    guard let leaf = SecCertificateCreateWithData(nil, identity.leafDER as CFData) else {
      TokenLog.error("Token.init: SecCertificateCreateWithData(leaf) nil")
      throw TokenError.certificateUnreadable
    }
    guard let profile = CardKeyProfile.resolve(fromCertificate: leaf) else {
      TokenLog.error("Token.init: unsupported key profile")
      throw TokenError.unsupportedKeyProfile
    }
    // Only publish an identity we can actually sign with. An RSA card is
    // recognized but the sign path is ECDSA-only for now; publishing a
    // canSign key we cannot service would offer Safari a certificate that
    // never prompts for PIN and always fails the handshake.
    guard SigningAlgorithmResolver.supportsSigning(profile) else {
      TokenLog.error("Token.init: \(profile) recognized but signing not yet supported")
      throw TokenError.unsupportedKeyProfile
    }
    guard let publicKey = SecCertificateCopyKey(leaf) else {
      TokenLog.error("Token.init: SecCertificateCopyKey(leaf) nil")
      throw TokenError.certificateUnreadable
    }
    self.keyProfile = profile
    self.leafPublicKey = publicKey
    let fingerprint = SHA256.hash(data: identity.leafDER)
      .map { String(format: "%02x", $0) }
      .joined()
    let instanceID = "\(fingerprint.prefix(Self.instanceFingerprintLength)).\(Self.contentsVersion)"
    super.init(
      smartCard: smartCard,
      aid: aid,
      instanceID: instanceID,
      tokenDriver: tokenDriver
    )
    TokenLog.info("Token.init: super.init done, publishing profile=\(String(describing: profile))")
    try publish(identity, leaf: leaf, profile: profile)
    // A fresh token means the card (re-)appeared: clear any cached PIN1 and
    // lift the disable latch a prior degradation may have set.
    CredentialMemory.pin1Cache.reset()
    TokenLog.info("Token.init: publish done")
  }

  /// Reads the leaf and (best-effort) issuer certificates and resolves
  /// the key profile, all in one exclusive card session.
  private static func readIdentity(from smartCard: TKSmartCard) throws -> PublishedIdentity {
    TokenLog.info("readIdentity: opening session")
    return try SmartCardChannel(smartCard).withSession { channel in
      let operations = CardOperations(channel: channel)
      TokenLog.info("readIdentity: selecting application")
      try operations.selectFineidApplication()
      TokenLog.info("readIdentity: reading leaf EF.4331")
      let leaf = try operations.readCertificate(.authentication)
      TokenLog.info("readIdentity: leaf \(leaf.count) bytes; reading issuer EF.4336")
      let issuer = try? operations.readCertificate(.issuing)
      TokenLog.info("readIdentity: issuer \(issuer?.count ?? -1) bytes")
      return PublishedIdentity(leafDER: leaf, issuerDER: issuer)
    }
  }

  // The @objc requirement is throwing; keep `throws` for the bridge.
  // swiftlint:disable:next unneeded_throws_rethrows
  internal func createSession(_: TKToken) throws -> TKTokenSession {
    TokenSession(token: self)
  }

  /// Builds and fills the keychain contents from the read identity.
  private func publish(
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
      "publish: filling \(items.count) items, keychainContents=\(keychainContents != nil)"
    )
    keychainContents?.fill(with: items)
  }
}
