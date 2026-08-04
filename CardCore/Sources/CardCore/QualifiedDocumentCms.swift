import CryptoKit
import Foundation

/// The CMS SignedData of one PAdES qualified signature (RFC 5652,
/// ETSI EN 319 142-1).
///
/// The PAdES profile is strict about what the signed attributes are:
/// content-type, message-digest and signing-certificate-v2, and
/// nothing else - a signing-time attribute downgrades the signature,
/// because the PDF `/M` entry owns that fact. The attributes are
/// signed in their SET form and carried retagged, the signature value
/// is the card's raw pair re-encoded as DER, and the only certificate
/// embedded is the signer's own: the chain travels in the document
/// security store, not here.
public enum QualifiedDocumentCms {
  /// A failure to assemble the structure.
  public enum AssemblyError: Error, Equatable {
    /// The signer certificate did not parse far enough to name its
    /// issuer and serial.
    case certificateUnparseable

    /// The card's raw signature was empty or odd-length.
    case signatureMalformed
  }

  /// The signed attributes in their SET form: what the card digests
  /// and signs (SHA-384 of exactly these bytes).
  public static func signedAttributes(
    byteRangeDigest: Data,
    signerCertificate: Data
  ) -> Data {
    let contentType = attribute(
      SignOids.contentType,
      value: DerEncoder.objectIdentifier(SignOids.data)
    )
    let messageDigest = attribute(
      SignOids.messageDigest,
      value: DerEncoder.octetString(byteRangeDigest)
    )
    let certificateHash = Data(SHA384.hash(data: signerCertificate))
    // ESSCertIDv2 carries its hash algorithm explicitly because the
    // DER DEFAULT is SHA-256 and this is not (RFC 5035).
    let essCertId = DerEncoder.sequence([
      sha384AlgorithmIdentifier(),
      DerEncoder.octetString(certificateHash),
    ])
    let signingCertificate = attribute(
      SignOids.signingCertificateV2,
      value: DerEncoder.sequence([DerEncoder.sequence([essCertId])])
    )
    return DerEncoder.setOf([contentType, messageDigest, signingCertificate])
  }

  /// The complete ContentInfo, ready for the document's hole.
  ///
  /// `signedAttributesSet` must be the exact bytes the card signed;
  /// they are retagged, never rebuilt. `rawSignature` is the card's
  /// r-then-s pair. Timestamp tokens become one unsigned-attribute
  /// instance each, sorted and deduplicated.
  public static func assemble(
    signedAttributesSet: Data,
    rawSignature: Data,
    signerCertificate: Data,
    timestampTokens: [Data]
  ) throws -> Data {
    let identity = try issuerAndSerial(of: signerCertificate)
    let signature = try ecdsaSignature(rawSignature)
    var signerInfo: [Data] = [
      DerEncoder.integer(SignOids.signerInfoVersion),
      identity,
      sha384AlgorithmIdentifier(),
      DerEncoder.retagged(
        signedAttributesSet, to: DerValues.tagContext0Constructed
      ),
      ecdsaWithSha384AlgorithmIdentifier(),
      DerEncoder.octetString(signature),
    ]
    if !timestampTokens.isEmpty {
      let instances = timestampTokens.map { token in
        attribute(SignOids.signatureTimestampToken, value: token)
      }
      let unique = Array(Set(instances)).sorted { left, right in
        left.lexicographicallyPrecedes(right)
      }
      signerInfo.append(
        DerEncoder.retagged(
          DerEncoder.tlv(DerValues.tagSet, unique.reduce(Data(), +)),
          to: DerValues.tagContext1Constructed
        )
      )
    }
    let signedData = DerEncoder.sequence([
      DerEncoder.integer(SignOids.cmsVersion),
      DerEncoder.tlv(DerValues.tagSet, sha384AlgorithmIdentifier()),
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.data)]),
      DerEncoder.retagged(
        DerEncoder.tlv(DerValues.tagSet, signerCertificate),
        to: DerValues.tagContext0Constructed
      ),
      DerEncoder.tlv(
        DerValues.tagSet, DerEncoder.sequence(signerInfo)
      ),
    ])
    return DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.signedData),
      DerEncoder.tlv(DerValues.tagContext0Constructed, signedData),
    ])
  }

  /// The card's raw r-then-s pair as DER.
  ///
  /// A signature timestamp is taken over the signature value as it is
  /// stored in the CMS, which is this form - not the card's raw pair.
  public static func derSignature(_ raw: Data) throws -> Data {
    try Self.ecdsaSignature(raw)
  }

  /// One attribute: its OID and one value in a SET.
  private static func attribute(_ oid: String, value: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(oid),
      DerEncoder.tlv(DerValues.tagSet, value),
    ])
  }

  /// SHA-384 with absent parameters (RFC 5754).
  private static func sha384AlgorithmIdentifier() -> Data {
    DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha384)])
  }

  /// ecdsa-with-SHA384 with no parameters (RFC 5758).
  private static func ecdsaWithSha384AlgorithmIdentifier() -> Data {
    DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha384)])
  }

  /// The card's raw r-then-s pair as the DER pair DER demands.
  private static func ecdsaSignature(_ raw: Data) throws -> Data {
    guard
      !raw.isEmpty,
      raw.count.isMultiple(of: SignOids.ecdsaSignatureParts)
    else {
      throw AssemblyError.signatureMalformed
    }
    let half = raw.count / SignOids.ecdsaSignatureParts
    return DerEncoder.sequence([
      DerEncoder.unsignedInteger(raw.prefix(half)),
      DerEncoder.unsignedInteger(raw.suffix(half)),
    ])
  }

  /// IssuerAndSerialNumber from the certificate, byte-identical.
  ///
  /// The issuer Name is copied raw; the serial keeps its exact value
  /// octets. TBSCertificate is walked just far enough: an optional
  /// version, the serial INTEGER, the signature algorithm, the issuer
  /// (RFC 5280 §4.1).
  private static func issuerAndSerial(of certificate: Data) throws -> Data {
    var outer = DerReader(certificate)
    guard let certificateElement = outer.next() else {
      throw AssemblyError.certificateUnparseable
    }
    var certificateReader = DerReader(certificate, within: certificateElement)
    guard let tbs = certificateReader.next() else {
      throw AssemblyError.certificateUnparseable
    }
    var tbsReader = DerReader(certificate, within: tbs)
    guard var element = tbsReader.next() else {
      throw AssemblyError.certificateUnparseable
    }
    if element.tag == DerValues.tagContext0Constructed {
      guard let following = tbsReader.next() else {
        throw AssemblyError.certificateUnparseable
      }
      element = following
    }
    guard element.tag == DerValues.tagInteger else {
      throw AssemblyError.certificateUnparseable
    }
    let serial = tbsReader.data(of: element)
    guard tbsReader.next() != nil, let issuer = tbsReader.next() else {
      throw AssemblyError.certificateUnparseable
    }
    return DerEncoder.sequence([tbsReader.data(of: issuer), serial])
  }
}
