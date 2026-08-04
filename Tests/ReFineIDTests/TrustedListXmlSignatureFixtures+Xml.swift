import Foundation
import Security

@testable import ReFineID

extension TrustedListXmlSignatureFixtures {
  /// DER INTEGER identifier octet.
  private static let derIntegerTag: UInt8 = 0x02

  /// DER long-form length marker.
  private static let derLongFormMask: UInt8 = 0x80

  /// DER count bits in a long-form length octet.
  private static let derLengthCountMask: UInt8 = 0x7F

  /// DER SEQUENCE identifier octet.
  private static let derSequenceTag: UInt8 = 0x30

  /// Number of bits in one byte.
  private static let bitsPerByte = 8

  /// Addition used to round a bit count up to whole bytes.
  private static let byteRoundingAdjustment = 7

  /// Produces the XML skeleton whose digest and signature markers are filled.
  internal static func skeleton(
    profile: Profile,
    signer: Signer,
    window: Window,
    schemeContent: String,
    xadesBinding: XadesBinding
  ) -> String {
    let xml = TrustedListXmlSignature.Xml.self
    let namespaces =
      "xmlns=\"\(xml.trustedListNamespace)\" "
      + "xmlns:ds=\"\(xml.signatureNamespace)\" "
      + "xmlns:xades=\"\(xml.xadesNamespace)\""
    return """
      <TrustServiceStatusList \(namespaces) Id="list">
        <SchemeInformation>
          <TSLVersionIdentifier>6</TSLVersionIdentifier>
          <TSLSequenceNumber>1</TSLSequenceNumber>
          \(schemeContent)
          <ListIssueDateTime>\(window.issuedAt)</ListIssueDateTime>
          <NextUpdate><dateTime>\(window.nextUpdate)</dateTime></NextUpdate>
        </SchemeInformation>
        \(Self.signatureSkeleton(
          profile: profile,
          signer: signer,
          window: window,
          xadesBinding: xadesBinding
        ))
      </TrustServiceStatusList>
      """
  }

  /// XMLDSig and XAdES subtree placed inside the fixture TSL.
  private static func signatureSkeleton(
    profile: Profile,
    signer: Signer,
    window: Window,
    xadesBinding: XadesBinding
  ) -> String {
    let xml = TrustedListXmlSignature.Xml.self
    return """
      <ds:Signature Id="signature">
        <ds:SignedInfo>
          <ds:CanonicalizationMethod Algorithm="\(xml.canonicalization)"/>
          \(profile.signatureMethod)
          <ds:Reference URI="#list">
            <ds:Transforms>
              <ds:Transform Algorithm="\(xml.envelopedTransform)"/>
              <ds:Transform Algorithm="\(xml.canonicalization)"/>
            </ds:Transforms>
            <ds:DigestMethod Algorithm="\(profile.digestUri)"/>
            <ds:DigestValue>\(Self.documentDigestMarker)</ds:DigestValue>
          </ds:Reference>
          <ds:Reference Type="\(xml.signedPropertiesType)" URI="#properties">
            <ds:Transforms>
              <ds:Transform Algorithm="\(xml.canonicalization)"/>
            </ds:Transforms>
            <ds:DigestMethod Algorithm="\(profile.digestUri)"/>
            <ds:DigestValue>\(Self.propertiesDigestMarker)</ds:DigestValue>
          </ds:Reference>
        </ds:SignedInfo>
        <ds:SignatureValue>\(Self.signatureValueMarker)</ds:SignatureValue>
        <ds:KeyInfo>
          <ds:X509Data>
            <ds:X509Certificate>\(signer.certificate.base64EncodedString())</ds:X509Certificate>
          </ds:X509Data>
        </ds:KeyInfo>
        <ds:Object>
          <xades:QualifyingProperties Target="#signature">
            <xades:SignedProperties Id="properties">
              <xades:SignedSignatureProperties>
                <xades:SigningTime>\(window.issuedAt)</xades:SigningTime>
                \(Self.signingCertificate(
                  profile: profile,
                  signer: signer,
                  binding: xadesBinding
                ))
              </xades:SignedSignatureProperties>
            </xades:SignedProperties>
          </xades:QualifyingProperties>
        </ds:Object>
      </ds:Signature>
      """
  }

  /// SigningCertificateV2 markup included in the signed properties.
  private static func signingCertificate(
    profile: Profile,
    signer: Signer,
    binding: XadesBinding
  ) -> String {
    guard binding != .omitted else { return "" }
    let actual = profile.digest.digest(signer.certificate)
    let digest: Data
    switch binding {
    case .matching:
      digest = actual
    case .mismatched:
      digest = Data(repeating: 0, count: actual.count)
    case .omitted:
      return ""
    }
    return """
      <xades:SigningCertificateV2>
        <xades:Cert>
          <xades:CertDigest>
            <ds:DigestMethod Algorithm="\(profile.digestUri)"/>
            <ds:DigestValue>\(digest.base64EncodedString())</ds:DigestValue>
          </xades:CertDigest>
        </xades:Cert>
      </xades:SigningCertificateV2>
      """
  }

  /// Signs canonical SignedInfo and emits XMLDSig's signature shape.
  internal static func sign(
    _ canonical: Data,
    profile: Profile,
    key: SecKey
  ) throws -> Data {
    var error: Unmanaged<CFError>?
    guard
      let created = SecKeyCreateSignature(
        key,
        profile.securityAlgorithm,
        canonical as CFData,
        &error
      )
    else {
      _ = error?.takeRetainedValue()
      throw Failure.signatureCreation
    }
    let signature = created as Data
    guard
      case .rsa = profile.keyKind
    else {
      guard
        let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
        let bitCount = attributes[kSecAttrKeySizeInBits] as? Int
      else {
        throw Failure.keyCreation
      }
      let componentBytes =
        (bitCount + Self.byteRoundingAdjustment) / Self.bitsPerByte
      return try Self.rawEcdsaSignature(
        from: signature,
        componentBytes: componentBytes
      )
    }
    return signature
  }

  /// Converts Security's X9.62 ECDSA result to XMLDSig raw r||s.
  private static func rawEcdsaSignature(
    from der: Data,
    componentBytes: Int
  ) throws -> Data {
    let bytes = Array(der)
    var cursor = 0
    guard
      try Self.readTag(from: bytes, cursor: &cursor) == Self.derSequenceTag,
      let sequenceLength = Self.readLength(from: bytes, cursor: &cursor),
      cursor + sequenceLength == bytes.count,
      try Self.readTag(from: bytes, cursor: &cursor) == Self.derIntegerTag,
      let firstLength = Self.readLength(from: bytes, cursor: &cursor),
      cursor + firstLength <= bytes.count
    else {
      throw Failure.signatureCreation
    }
    let first = Data(bytes[cursor..<(cursor + firstLength)])
    cursor += firstLength
    guard
      try Self.readTag(from: bytes, cursor: &cursor) == Self.derIntegerTag,
      let secondLength = Self.readLength(from: bytes, cursor: &cursor),
      cursor + secondLength == bytes.count
    else {
      throw Failure.signatureCreation
    }
    let second = Data(bytes[cursor..<(cursor + secondLength)])
    return try Self.fixedWidth(first, count: componentBytes)
      + Self.fixedWidth(second, count: componentBytes)
  }

  /// Reads one required DER tag.
  private static func readTag(
    from bytes: [UInt8],
    cursor: inout Int
  ) throws -> UInt8 {
    guard cursor < bytes.count else { throw Failure.signatureCreation }
    defer { cursor += 1 }
    return bytes[cursor]
  }

  /// Reads a short or small long-form DER length.
  private static func readLength(
    from bytes: [UInt8],
    cursor: inout Int
  ) -> Int? {
    guard cursor < bytes.count else { return nil }
    let first = bytes[cursor]
    cursor += 1
    if first & Self.derLongFormMask == 0 { return Int(first) }
    let count = Int(first & Self.derLengthCountMask)
    guard count > 0, cursor + count <= bytes.count else { return nil }
    var length = 0
    for byte in bytes[cursor..<(cursor + count)] {
      length = length << UInt8.bitWidth | Int(byte)
    }
    cursor += count
    return length
  }

  /// Removes DER's sign octet and left-pads one unsigned integer.
  private static func fixedWidth(_ integer: Data, count: Int) throws -> Data {
    let magnitude = Data(integer.drop { byte in byte == 0 })
    guard magnitude.count <= count else { throw Failure.signatureCreation }
    return Data(repeating: 0, count: count - magnitude.count) + magnitude
  }
}
