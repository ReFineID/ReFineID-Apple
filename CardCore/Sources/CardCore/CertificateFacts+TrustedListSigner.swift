import Foundation

extension CertificateFacts {
  /// Whether an ETSI trusted-list signer certificate is an end entity whose
  /// declared KeyUsage, when present, permits a content signature.
  ///
  /// Trusted-list signers in the EU directory do not have one interoperable
  /// EKU profile, so this deliberately does not gate on extended key usage.
  /// Omitted BasicConstraints denotes an end entity; an explicit CA assertion
  /// is always rejected. Omitted KeyUsage imposes no restriction, while a
  /// present KeyUsage must contain digitalSignature or contentCommitment.
  public static func isPermittedTrustedListSigner(der: Data) -> Bool {
    guard var extensions = Self.trustedListExtensions(in: der) else {
      return false
    }
    var foundBasicConstraints = false
    var foundKeyUsage = false
    while let entry = extensions.next() {
      guard entry.tag == DerValues.tagSequence else { return false }
      if Self.isExtension(
        entry,
        identifier: SignOids.basicConstraints,
        in: der
      ) {
        guard
          !foundBasicConstraints,
          let payload = Self.trustedListExtensionPayload(entry, in: der),
          Self.basicConstraintsPermitTrustedListSigner(payload)
        else { return false }
        foundBasicConstraints = true
      } else if Self.isExtension(
        entry,
        identifier: SignOids.keyUsage,
        in: der
      ) {
        guard
          !foundKeyUsage,
          let payload = Self.trustedListExtensionPayload(entry, in: der),
          Self.keyUsagePermitsTrustedListSignature(payload)
        else { return false }
        foundKeyUsage = true
      }
    }
    return extensions.isAtEnd
  }

  /// The certificate Extensions sequence after the fixed TBSCertificate fields.
  private static func trustedListExtensions(
    in der: Data
  ) -> DerReader? {
    guard let tbs = Self.trustedListTbs(in: der) else { return nil }
    var fields = DerReader(der, within: tbs)
    guard Self.consumeTrustedListCertificatePrefix(&fields) else { return nil }
    let selection = Self.trustedListExtensionWrapper(in: &fields)
    guard selection.isValid, fields.isAtEnd else { return nil }
    guard let wrapper = selection.element else { return DerReader(Data()) }
    var wrapped = DerReader(der, within: wrapper)
    guard
      let sequence = wrapped.next(),
      sequence.tag == DerValues.tagSequence,
      wrapped.isAtEnd
    else { return nil }
    return DerReader(der, within: sequence)
  }

  /// The sole TBSCertificate inside one complete certificate encoding.
  private static func trustedListTbs(
    in der: Data
  ) -> DerReader.Element? {
    var outer = DerReader(der)
    guard
      let certificate = outer.next(),
      certificate.tag == DerValues.tagSequence,
      outer.isAtEnd
    else { return nil }
    var certificateReader = DerReader(der, within: certificate)
    return certificateReader.next()
  }

  /// Consumes version through SubjectPublicKeyInfo.
  private static func consumeTrustedListCertificatePrefix(
    _ fields: inout DerReader
  ) -> Bool {
    guard var serial = fields.next() else { return false }
    if serial.tag == DerValues.tagContext0Constructed {
      guard let following = fields.next() else { return false }
      serial = following
    }
    return serial.tag == DerValues.tagInteger
      && fields.next() != nil
      && fields.next() != nil
      && fields.next() != nil
      && fields.next() != nil
      && fields.next() != nil
  }

  /// Finds at most one Extensions wrapper among optional trailing fields.
  private static func trustedListExtensionWrapper(
    in fields: inout DerReader
  ) -> (element: DerReader.Element?, isValid: Bool) {
    var wrapper: DerReader.Element?
    while let field = fields.next() {
      if field.tag == DerValues.tagContext3Constructed {
        guard wrapper == nil else { return (nil, false) }
        wrapper = field
      }
    }
    return (wrapper, true)
  }

  /// Whether one extension entry carries the requested identifier.
  private static func isExtension(
    _ entry: DerReader.Element,
    identifier: String,
    in der: Data
  ) -> Bool {
    var reader = DerReader(der, within: entry)
    guard let oid = reader.next() else { return false }
    return reader.data(of: oid) == DerEncoder.objectIdentifier(identifier)
  }

  /// The DER value wrapped by one recognized Extension entry.
  private static func trustedListExtensionPayload(
    _ entry: DerReader.Element,
    in der: Data
  ) -> Data? {
    var reader = DerReader(der, within: entry)
    guard reader.next() != nil, var value = reader.next() else { return nil }
    if value.tag == DerValues.tagBoolean {
      let critical = reader.contentData(of: value)
      guard
        critical == Data([0]) || critical == Data([DerValues.booleanTrue]),
        let following = reader.next()
      else { return nil }
      value = following
    }
    guard value.tag == DerValues.tagOctetString, reader.isAtEnd else {
      return nil
    }
    return reader.contentData(of: value)
  }

  /// BasicConstraints permits a TSL signer unless it asserts CA=true.
  ///
  /// Estonia's authenticated current TSL signer encodes the non-conforming
  /// but unambiguous `SEQUENCE { pathLenConstraint 0 }` shape. That exact
  /// integer-only end-entity form is accepted as a narrow interoperability
  /// exception; combinations of cA and pathLen remain rejected.
  private static func basicConstraintsPermitTrustedListSigner(
    _ encoded: Data
  ) -> Bool {
    var wrapped = DerReader(encoded)
    guard
      let sequence = wrapped.next(),
      sequence.tag == DerValues.tagSequence,
      wrapped.isAtEnd
    else { return false }
    var fields = DerReader(encoded, within: sequence)
    guard let field = fields.next() else { return fields.isAtEnd }
    guard fields.isAtEnd else { return false }
    if field.tag == DerValues.tagBoolean {
      return fields.contentData(of: field) == Data([0])
    }
    guard field.tag == DerValues.tagInteger else { return false }
    return fields.contentData(of: field) == Data([0])
  }

  /// A present KeyUsage must grant digitalSignature or contentCommitment.
  private static func keyUsagePermitsTrustedListSignature(
    _ encoded: Data
  ) -> Bool {
    var wrapped = DerReader(encoded)
    guard
      let bitString = wrapped.next(),
      bitString.tag == DerValues.tagBitString,
      wrapped.isAtEnd
    else { return false }
    let content = wrapped.contentData(of: bitString)
    guard
      let unusedBits = content.first,
      unusedBits < UInt8.bitWidth,
      let firstUsageByte = content.dropFirst().first,
      let lastUsageByte = content.last
    else { return false }
    let unusedMask = UInt8.max >> (UInt8.bitWidth - Int(unusedBits))
    guard lastUsageByte & unusedMask == 0 else { return false }
    let digitalSignature = UInt8(1) << (UInt8.bitWidth - 1)
    let contentCommitment = digitalSignature >> 1
    return firstUsageByte & (digitalSignature | contentCommitment) != 0
  }
}
