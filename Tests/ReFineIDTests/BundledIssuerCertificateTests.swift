//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
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

    private static let organisationalResource =
      "fineid-intermediate-03-organisation-g4r"
    private static let organisationalCommonName =
      "DVV Organisational Certificates - G4R"
    private static let organisationalSha256 =
      "DFC3E965176F883A9CF0F68CEAEEAB663EDFD8E79DE3294373C28A856984006F"

    /// Reads one PEM resource from the app bundle as canonical DER.
    private static func issuer(resource: String) throws -> Data {
      let url = try #require(
        Bundle.main.url(forResource: resource, withExtension: "pem")
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

    /// One resource's bytes are the exact public certificate DVV
    /// identifies by this fingerprint and subject.
    private static func expectPinnedIdentity(
      resource: String,
      sha256: String,
      commonName: String
    ) throws {
      let der = try Self.issuer(resource: resource)
      let fingerprint = Data(SHA256.hash(data: der))
        .map { String(format: "%02X", $0) }
        .joined()
      #expect(fingerprint == sha256)

      let certificate = try #require(
        SecCertificateCreateWithData(nil, der as CFData)
      )
      #expect(
        SecCertificateCopySubjectSummary(certificate) as String?
          == commonName
      )
    }

    /// The shipped bytes are the exact public certificate DVV identifies.
    @Test
    internal func legacyCitizenIssuerHasPinnedIdentity() throws {
      try Self.expectPinnedIdentity(
        resource: Self.legacyResource,
        sha256: Self.legacySha256,
        commonName: Self.legacyCommonName
      )
    }

    /// The organization card's issuing CA ships pinned the same way.
    @Test
    internal func organisationalIssuerHasPinnedIdentity() throws {
      try Self.expectPinnedIdentity(
        resource: Self.organisationalResource,
        sha256: Self.organisationalSha256,
        commonName: Self.organisationalCommonName
      )
    }

    /// A leaf naming the legacy subject selects that exact bundled issuer.
    @Test
    internal func legacyIssuerNameSelectsLegacyResource() throws {
      let issuer = try Self.issuer(resource: Self.legacyResource)
      let facts = try #require(CertificateFacts(der: issuer))
      let leaf = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        issuerName: facts.subjectName
      )

      let matched = try #require(
        BundledIssuerCertificate.der(matching: leaf.certificate)
      )
      #expect(matched == issuer)
    }

    /// A leaf naming the organisational subject selects that resource,
    /// which is what closes an organization card's chain without the
    /// on-card read.
    @Test
    internal func organisationalIssuerNameSelectsOrganisationalResource() throws {
      let issuer = try Self.issuer(resource: Self.organisationalResource)
      let facts = try #require(CertificateFacts(der: issuer))
      let leaf = try SignerCertificateFixtures.makeSigner(
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
