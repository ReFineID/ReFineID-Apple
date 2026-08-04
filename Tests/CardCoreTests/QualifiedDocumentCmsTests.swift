import CardCore
import CryptoKit
import Foundation
import Testing

/// Direct checks for the PAdES CMS structure built around a card
/// signature.
@Suite
internal struct QualifiedDocumentCmsTests {
  /// A fixed certificate with the fields IssuerAndSerialNumber needs.
  private static let certificate = Self.decode(
    """
    MIIBszCCAVigAwIBAgIUMHfE/GmdSvG3+CQRxHSnFzfP2IwwCgYIKoZIzj0EAwIwHDEaMBgGA1UE
    AwwRUmVGaW5lSUQgVGVzdCBUU0EwHhcNMjYwODA0MDc1MzI1WhcNMzYwODAxMDc1MzI1WjAcMRow
    GAYDVQQDDBFSZUZpbmVJRCBUZXN0IFRTQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABEma/2Y8
    UqzBdNi9vlLoFQ+WHFW8PCTu67N0kmhjl18Eu0kEjTrtF6y5wF1VXf9ktFdnUJX+Rz6FES49kwG7
    cDujeDB2MB0GA1UdDgQWBBTY+L64mtIcQMUST9Jv2XCaRNeLmzAfBgNVHSMEGDAWgBTY+L64mtIc
    QMUST9Jv2XCaRNeLmzAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIGwDAWBgNVHSUBAf8EDDAK
    BggrBgEFBQcDCDAKBggqhkjOPQQDAgNJADBGAiEAwvyfmlibx6Pf8KmrY7VfgYwxbr56A80RBza/
    J4cPYlECIQCYsi5iogIH1DrFGEDBDrUrjaanfMOXp8GithjIM97ohg==
    """
  )

  /// Base64 fixture text with line breaks ignored.
  private static func decode(_ encoded: String) -> Data {
    Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) ?? Data()
  }

  /// The card signs attributes carrying the exact PDF digest and the
  /// SHA-384 hash of its signing certificate.
  @Test
  internal func signedAttributesBindDocumentAndCertificate() {
    let documentDigest = Data(repeating: 0xA5, count: 48)

    let attributes = QualifiedDocumentCms.signedAttributes(
      byteRangeDigest: documentDigest,
      signerCertificate: Self.certificate
    )

    #expect(attributes.contains(DerEncoder.octetString(documentDigest)))
    #expect(
      attributes.contains(
        DerEncoder.octetString(
          Data(SHA384.hash(data: Self.certificate))
        )
      )
    )
  }

  /// The raw P-384 r||s pair is converted to the exact DER pair that a
  /// signature timestamp covers.
  @Test
  internal func rawSignatureIsConvertedToDer() throws {
    let first = Data(repeating: 0x80, count: 48)
    let second = Data(repeating: 0x01, count: 48)

    let converted = try QualifiedDocumentCms.derSignature(first + second)

    #expect(
      converted
        == DerEncoder.sequence([
          DerEncoder.unsignedInteger(first),
          DerEncoder.unsignedInteger(second),
        ])
    )
  }

  /// The assembled SignedData carries the signer certificate and the
  /// supplied signature timestamp token.
  @Test
  internal func assembledCmsCarriesCertificateAndTimestamp() throws {
    let attributes = QualifiedDocumentCms.signedAttributes(
      byteRangeDigest: Data(repeating: 0xA5, count: 48),
      signerCertificate: Self.certificate
    )
    let rawSignature = Data(repeating: 0x01, count: 96)
    let timestamp = DerEncoder.sequence([DerEncoder.integer(7)])

    let cms = try QualifiedDocumentCms.assemble(
      signedAttributesSet: attributes,
      rawSignature: rawSignature,
      signerCertificate: Self.certificate,
      timestampTokens: [timestamp]
    )

    #expect(CmsCertificates.inside(cms) == [Self.certificate])
    #expect(cms.contains(timestamp))
  }

  /// Empty, odd-length, or unparseable inputs fail rather than producing
  /// a CMS value that a validator must guess about.
  @Test
  internal func malformedInputsAreRefused() {
    #expect(throws: QualifiedDocumentCms.AssemblyError.signatureMalformed) {
      _ = try QualifiedDocumentCms.derSignature(Data())
    }
    #expect(throws: QualifiedDocumentCms.AssemblyError.signatureMalformed) {
      _ = try QualifiedDocumentCms.derSignature(Data(repeating: 1, count: 3))
    }
    #expect(throws: QualifiedDocumentCms.AssemblyError.certificateUnparseable) {
      _ = try QualifiedDocumentCms.assemble(
        signedAttributesSet: DerEncoder.setOf([]),
        rawSignature: Data(repeating: 1, count: 2),
        signerCertificate: Data("not a certificate".utf8),
        timestampTokens: []
      )
    }
  }
}
