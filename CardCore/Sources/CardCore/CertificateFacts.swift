import Foundation

/// The certificate fields chain-building and revocation need
/// (RFC 5280).
///
/// Read straight from the DER rather than through the platform's
/// certificate API, because what an OCSP responder compares is the
/// exact encoded issuer Name and the exact serialNumber octets, and a
/// re-encoding of either produces hashes that match nothing.
public struct CertificateFacts {
  /// The issuer Name, exactly as encoded in this certificate.
  public let issuerName: Data

  /// The subject Name, exactly as encoded.
  public let subjectName: Data

  /// The serialNumber value octets, without the tag or length.
  public let serialNumber: Data

  /// The subjectPublicKey bit string's bits, without the unused-bits
  /// octet - what an OCSP CertID hashes.
  public let publicKeyBits: Data

  /// Where the issuer's certificate can be fetched (AIA caIssuers).
  public let issuerCertificateUrls: [String]

  /// Where this certificate's status can be asked (AIA OCSP).
  public let ocspUrls: [String]

  /// Whether this certificate issued itself, which ends a chain walk.
  public var isSelfIssued: Bool {
    issuerName == subjectName
  }

  /// Reads what is needed, or nil when the certificate does not parse
  /// as far as those fields.
  public init?(der: Data) {
    var outer = DerReader(der)
    guard
      let certificate = outer.next(),
      certificate.tag == DerValues.tagSequence
    else {
      return nil
    }
    var certificateReader = DerReader(der, within: certificate)
    guard let tbs = certificateReader.next() else { return nil }
    var reader = DerReader(der, within: tbs)
    guard var element = reader.next() else { return nil }
    if element.tag == DerValues.tagContext0Constructed {
      guard let following = reader.next() else { return nil }
      element = following
    }
    guard element.tag == DerValues.tagInteger else { return nil }
    self.serialNumber = reader.contentData(of: element)
    guard
      reader.next() != nil,
      let issuer = reader.next(),
      reader.next() != nil,
      let subject = reader.next(),
      let publicKeyInfo = reader.next()
    else {
      return nil
    }
    self.issuerName = reader.data(of: issuer)
    self.subjectName = reader.data(of: subject)
    guard let bits = Self.keyBits(of: publicKeyInfo, in: der) else {
      return nil
    }
    self.publicKeyBits = bits
    let access = Self.accessDescriptions(in: der, reader: &reader)
    self.issuerCertificateUrls = access.issuers
    self.ocspUrls = access.ocsp
  }

  /// The subjectPublicKey bits, dropping the unused-bits count.
  private static func keyBits(
    of publicKeyInfo: DerReader.Element,
    in der: Data
  ) -> Data? {
    var reader = DerReader(der, within: publicKeyInfo)
    guard
      reader.next() != nil,
      let bitString = reader.next(),
      bitString.tag == DerValues.tagBitString
    else {
      return nil
    }
    let content = reader.contentData(of: bitString)
    guard !content.isEmpty else { return nil }
    return content.dropFirst()
  }

  /// The AIA URLs, split by access method.
  ///
  /// The extension is optional and so is every field in it; a
  /// certificate that names no issuer URL simply ends the walk, and
  /// one that names no responder falls back to a revocation list.
  private static func accessDescriptions(
    in der: Data,
    reader: inout DerReader
  ) -> (issuers: [String], ocsp: [String]) {
    while let element = reader.next() {
      guard element.tag == DerValues.tagContext3Constructed else { continue }
      var wrapper = DerReader(der, within: element)
      guard let extensions = wrapper.next() else { continue }
      var list = DerReader(der, within: extensions)
      while let entry = list.next() {
        if let value = Self.accessExtensionValue(entry, in: der) {
          return Self.urls(in: value, der: der)
        }
      }
    }
    return ([], [])
  }

  /// The extnValue of one access extension, or nil for anything else.
  private static func accessExtensionValue(
    _ entry: DerReader.Element,
    in der: Data
  ) -> DerReader.Element? {
    var reader = DerReader(der, within: entry)
    guard
      let oid = reader.next(),
      reader.data(of: oid)
        == DerEncoder.objectIdentifier(SignOids.authorityInfoAccess),
      var value = reader.next()
    else {
      return nil
    }
    // The criticality flag is optional and precedes the value.
    if value.tag == DerValues.tagBoolean {
      guard let following = reader.next() else { return nil }
      value = following
    }
    return value
  }

  /// The URLs inside one access extension, by method.
  private static func urls(
    in value: DerReader.Element,
    der: Data
  ) -> (issuers: [String], ocsp: [String]) {
    var issuers: [String] = []
    var responders: [String] = []
    var valueReader = DerReader(der, within: value)
    guard let descriptions = valueReader.next() else {
      return ([], [])
    }
    var list = DerReader(der, within: descriptions)
    while let description = list.next() {
      var parts = DerReader(der, within: description)
      guard
        let method = parts.next(),
        let location = parts.next(),
        location.tag == DerValues.tagContext6Primitive,
        let url = String(
          bytes: parts.contentData(of: location), encoding: .ascii
        )
      else {
        continue
      }
      let methodOid = parts.data(of: method)
      if methodOid == DerEncoder.objectIdentifier(SignOids.caIssuers) {
        issuers.append(url)
      } else if methodOid == DerEncoder.objectIdentifier(SignOids.ocsp) {
        responders.append(url)
      }
    }
    return (issuers, responders)
  }
}
