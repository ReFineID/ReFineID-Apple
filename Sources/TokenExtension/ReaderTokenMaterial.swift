import CardCore
import Security

/// Validated material needed to mint one reader-backed token.
internal struct ReaderTokenMaterial {
  /// Certificates and complete card serial read in one card session.
  internal let identity: PublishedIdentity

  /// CAN used when the reader reached the card over contactless.
  internal let accessNumber: CardAccessNumber?

  /// Parsed authentication certificate.
  internal let leaf: SecCertificate

  /// Authentication key profile derived from the certificate.
  internal let profile: CardKeyProfile

  /// Public authentication key used to verify every card signature.
  internal let publicKey: SecKey

  /// Stable token identity derived from the printed card serial.
  internal let instanceID: CardInstanceIdentifier
}
