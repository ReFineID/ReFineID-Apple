/// The object identifiers document signing speaks, in dotted notation.
///
/// Encoded arithmetically by `DerEncoder.objectIdentifier`; the dotted
/// form is the named constant, so no encoded OID byte exists outside
/// the encoder.
internal enum SignOids {
  /// An ECDSA signature is the pair (r, s), so the card's raw answer
  /// splits in two equal halves.
  internal static let ecdsaSignatureParts: Int = 2

  /// CMS SignedData version 1: the version PAdES writes, since it
  /// carries no attribute certificates and no OCSP in the CMS itself
  /// (RFC 5652 §5.1).
  internal static let cmsVersion: Int = 1

  /// SignerInfo version 1: the issuer-and-serial form (RFC 5652 §5.3).
  internal static let signerInfoVersion: Int = 1

  /// TimeStampReq version 1, the only one defined (RFC 3161 §2.4.1).
  internal static let timestampRequestVersion: Int = 1

  /// TSTInfo version 1, the only one defined (RFC 3161 §2.4.2).
  internal static let tstInfoVersion: Int = 1

  /// PKIStatus values that carry a usable token: granted, and granted
  /// with modifications (RFC 3161 §2.4.2).
  internal static let grantedStatuses: Set<Int> = [0, 1]

  /// id-data (RFC 5652).
  internal static let data = "1.2.840.113549.1.7.1"

  /// id-signedData (RFC 5652).
  internal static let signedData = "1.2.840.113549.1.7.2"

  /// id-contentType signed attribute (RFC 5652).
  internal static let contentType = "1.2.840.113549.1.9.3"

  /// id-messageDigest signed attribute (RFC 5652).
  internal static let messageDigest = "1.2.840.113549.1.9.4"

  /// id-aa-signingCertificateV2 (RFC 5035).
  internal static let signingCertificateV2 = "1.2.840.113549.1.9.16.2.47"

  /// id-aa-signatureTimeStampToken (RFC 3161 appendix A).
  internal static let signatureTimestampToken = "1.2.840.113549.1.9.16.2.14"

  /// id-ct-TSTInfo (RFC 3161).
  internal static let tstInfo = "1.2.840.113549.1.9.16.1.4"

  /// SHA-384 (RFC 5754); parameters absent, never NULL.
  internal static let sha384 = "2.16.840.1.101.3.4.2.2"

  /// ecdsa-with-SHA384 (RFC 5758); no parameters.
  internal static let ecdsaWithSha384 = "1.2.840.10045.4.3.3"

  /// SHA-1, the OCSP CertID hash (RFC 6960 mandates support).
  internal static let sha1 = "1.3.14.3.2.26"

  /// id-pkix-ocsp-nonce (RFC 8954).
  internal static let ocspNonce = "1.3.6.1.5.5.7.48.1.2"

  /// id-pkix-ocsp-basic (RFC 6960).
  internal static let ocspBasic = "1.3.6.1.5.5.7.48.1.1"
}
