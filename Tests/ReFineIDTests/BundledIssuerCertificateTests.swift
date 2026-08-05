#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation
  import Security
  import Testing

  /// The public issuer resources that close supported FINEID card paths.
  @Suite
  internal struct BundledIssuerCertificateTests {
    private static let legacyResource = "fineid-intermediate-00-citizen-g3"
    private static let legacyCommonName =
      "VRK Gov. CA for Citizen Certificates - G3"
    private static let legacySha256 =
      "39A835B14B6B6313F778371C79CB434DD518C8FD325B749D9BE669DFF20384E8"

    /// Reads one PEM resource from the app bundle as canonical DER.
    private static func legacyIssuer() throws -> Data {
      let url = try #require(
        Bundle.main.url(
          forResource: Self.legacyResource,
          withExtension: "pem"
        )
      )
      let bytes = try Data(contentsOf: url)
      let text = try #require(String(data: bytes, encoding: .ascii))
      let base64 =
        text
        .split(whereSeparator: \.isNewline)
        .filter { !$0.hasPrefix("-----") }
        .joined()
      return try #require(Data(base64Encoded: String(base64)))
    }

    /// The shipped bytes are the exact public certificate DVV identifies.
    @Test
    internal func legacyCitizenIssuerHasPinnedIdentity() throws {
      let der = try Self.legacyIssuer()
      let fingerprint = Data(SHA256.hash(data: der))
        .map { String(format: "%02X", $0) }
        .joined()
      #expect(fingerprint == Self.legacySha256)

      let certificate = try #require(
        SecCertificateCreateWithData(nil, der as CFData)
      )
      #expect(
        SecCertificateCopySubjectSummary(certificate) as String?
          == Self.legacyCommonName
      )
    }

    /// A leaf naming the legacy subject selects that exact bundled issuer.
    @Test
    internal func legacyIssuerNameSelectsLegacyResource() throws {
      let issuer = try Self.legacyIssuer()
      let facts = try #require(CertificateFacts(der: issuer))
      let leaf = try TrustedListXmlSignatureFixtures.makeSigner(
        for: .rsaSha256,
        issuerName: facts.subjectName
      )

      let matched = try #require(
        BundledIssuerCertificate.der(matching: leaf.certificate)
      )
      #expect(matched == issuer)
    }
  }

#endif
