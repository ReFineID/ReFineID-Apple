import CardCore
import CryptoTokenKit
import Foundation
import Security

/// Certificate and stored-prime validation performed before token publication.
extension Token {
  /// Reads and validates everything needed for one reader-backed token.
  internal static func validatedReaderMaterial(
    from smartCard: TKSmartCard
  ) throws -> ReaderTokenMaterial {
    TokenLog.info("Token.init: reading identity")
    let (identity, accessNumber) = try Self.readIdentity(from: smartCard)
    TokenLog.info(
      "Token.init: leaf=\(identity.leafDER.count) issuer=\(identity.issuerDER?.count ?? -1)"
    )
    guard let leaf = SecCertificateCreateWithData(nil, identity.leafDER as CFData) else {
      TokenLog.error("Token.init: SecCertificateCreateWithData(leaf) nil")
      throw TokenError.certificateUnreadable
    }
    let (profile, publicKey) = try Self.validatedSigningKey(in: leaf)
    guard let instanceID = CardInstanceIdentifier(tokenSerial: identity.tokenSerial) else {
      TokenLog.error("Token.init: token serial has no supported printed-card form")
      throw TokenError.unsupportedKeyProfile
    }
    return ReaderTokenMaterial(
      identity: identity,
      accessNumber: accessNumber,
      leaf: leaf,
      profile: profile,
      publicKey: publicKey,
      instanceID: instanceID
    )
  }

  /// Validates every piece of a stored contactless identity.
  internal static func validated(
    primed: PrimedIdentity,
    instanceID: CardInstanceIdentifier
  ) throws -> PrimedTokenMaterial {
    guard let accessNumber = CardAccessNumber(digits: primed.can) else {
      TokenLog.trace("Token.init(primed): stored card access number is not usable")
      throw TokenError.primeMissing
    }
    guard let leaf = SecCertificateCreateWithData(nil, primed.certDER as CFData) else {
      TokenLog.trace("Token.init(primed): stored leaf \(primed.certDER.count)B is not a cert")
      throw TokenError.certificateUnreadable
    }
    let (profile, publicKey) = try Self.validatedSigningKey(in: leaf)
    guard
      let serialText = primed.tokenSerial,
      let storedSerial = TokenSerial(value: serialText),
      CardInstanceIdentifier(tokenSerial: storedSerial) == instanceID
    else {
      TokenLog.trace("Token.init(primed): stored serial does not name this token")
      throw TokenError.primeMissing
    }
    return PrimedTokenMaterial(
      accessNumber: accessNumber,
      leaf: leaf,
      profile: profile,
      publicKey: publicKey,
      serial: storedSerial
    )
  }

  /// Resolves a leaf to one signing profile and its public key.
  private static func validatedSigningKey(
    in leaf: SecCertificate
  ) throws -> (profile: CardKeyProfile, publicKey: SecKey) {
    guard let profile = CardKeyProfile.resolve(fromCertificate: leaf) else {
      TokenLog.error("Token.init: unsupported key profile")
      throw TokenError.unsupportedKeyProfile
    }
    guard SigningAlgorithmResolver.supportsSigning(profile) else {
      TokenLog.error("Token.init: \(profile) recognized but signing not yet supported")
      throw TokenError.unsupportedKeyProfile
    }
    guard let publicKey = SecCertificateCopyKey(leaf) else {
      TokenLog.error("Token.init: SecCertificateCopyKey(leaf) nil")
      throw TokenError.certificateUnreadable
    }
    return (profile, publicKey)
  }
}
