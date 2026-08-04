import Foundation
import Testing

@testable import ReFineID

/// Direct checks for the XML boundary that supplies qualified TSA
/// identities to timestamp verification.
@Suite
internal struct EuTrustedListDirectoryTests {
  /// One valid pointer with its exact signer certificate and territory.
  private static func pointer(
    location: String,
    certificate: Data,
    territory: String
  ) -> String {
    """
    <OtherTSLPointer>
      <ServiceDigitalIdentities>
        <ServiceDigitalIdentity>
          <DigitalId>
            <X509Certificate>\(certificate.base64EncodedString())</X509Certificate>
          </DigitalId>
        </ServiceDigitalIdentity>
      </ServiceDigitalIdentities>
      <TSLLocation>\(location)</TSLLocation>
      <AdditionalInformation>
        <OtherInformation><SchemeTerritory>\(territory)</SchemeTerritory></OtherInformation>
        <OtherInformation><MimeType>application/vnd.etsi.tsl+xml</MimeType></OtherInformation>
      </AdditionalInformation>
    </OtherTSLPointer>
    """
  }

  /// The index reader accepts only XML forms, removes duplicates, and
  /// never follows itself.
  @Test
  internal func indexReturnsOnlyDistinctNationalXmlLocations() throws {
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    let first = Self.pointer(
      location: "http://example.test/a.xml",
      certificate: signer.certificate,
      territory: "FI"
    )
    let duplicate = Self.pointer(
      location: "http://example.test/a.xml",
      certificate: signer.certificate,
      territory: "FI"
    )
    let second = Self.pointer(
      location: "https://example.test/b.xtsl",
      certificate: signer.certificate,
      territory: "SE"
    )
    let index = Data(
      """
      <TrustServiceStatusList>
        \(first)
        \(duplicate)
        \(second)
        <OtherTSLPointer>
          <TSLLocation>https://example.test/readme.pdf</TSLLocation>
          <AdditionalInformation>
            <OtherInformation><MimeType>application/pdf</MimeType></OtherInformation>
          </AdditionalInformation>
        </OtherTSLPointer>
        <OtherTSLPointer><TSLLocation>https://ec.europa.eu/tools/lotl/eu-lotl.xml</TSLLocation></OtherTSLPointer>
      </TrustServiceStatusList>
      """.utf8
    )

    let pointers = try EuTrustedListDirectory.trustedListPointers(in: index)

    #expect(
      pointers.map(\.location) == [
        "http://example.test/a.xml",
        "https://example.test/b.xtsl",
      ]
    )
    #expect(pointers.allSatisfy { $0.signingCertificates == [signer.certificate] })
  }

  /// XML media type, rather than a filename suffix, identifies a
  /// current national list such as Denmark's extensionless pointer.
  @Test
  internal func authenticatedXmlMimeTypeAllowsExtensionlessLocation() throws {
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    let pointer = Self.pointer(
      location: "https://example.test/TSLDK_v6xml",
      certificate: signer.certificate,
      territory: "DK"
    )
    let index = Data(
      "<TrustServiceStatusList>\(pointer)</TrustServiceStatusList>".utf8
    )

    let pointers = try EuTrustedListDirectory.trustedListPointers(in: index)

    #expect(pointers.map(\.location) == ["https://example.test/TSLDK_v6xml"])
    #expect(pointers.map(\.territory) == ["DK"])
  }

  /// A pointer that looks like XML but lacks the authenticated XML
  /// media type cannot be silently omitted from a complete result.
  @Test
  internal func unsupportedCurrentPointerIsRejected() throws {
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    let index = Data(
      """
      <TrustServiceStatusList>
        <OtherTSLPointer>
          <ServiceDigitalIdentities>
            <ServiceDigitalIdentity><DigitalId>
              <X509Certificate>\(signer.certificate.base64EncodedString())</X509Certificate>
            </DigitalId></ServiceDigitalIdentity>
          </ServiceDigitalIdentities>
          <TSLLocation>https://example.test/current.xml</TSLLocation>
        </OtherTSLPointer>
      </TrustServiceStatusList>
      """.utf8
    )

    #expect(throws: EuTrustedListDirectory.Failure.unusableResponse) {
      try EuTrustedListDirectory.trustedListPointers(in: index)
    }
  }

  /// A declared current XML list must carry one usable HTTP(S)
  /// location; otherwise the directory cannot claim completeness.
  @Test
  internal func malformedCurrentXmlLocationIsRejected() throws {
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    let pointer = Self.pointer(
      location: "ftp://example.test/TSLDK_v6xml",
      certificate: signer.certificate,
      territory: "DK"
    )
    let index = Data(
      "<TrustServiceStatusList>\(pointer)</TrustServiceStatusList>".utf8
    )

    #expect(throws: EuTrustedListDirectory.Failure.unusableResponse) {
      try EuTrustedListDirectory.trustedListPointers(in: index)
    }
  }

  /// The authenticated signer candidates of a current XML pointer
  /// must themselves be syntactically valid X.509 certificates.
  @Test
  internal func malformedPointerSignerCertificateIsRejected() throws {
    let malformed = Data("not an X.509 certificate".utf8)
    let pointer = Self.pointer(
      location: "https://example.test/current.xml",
      certificate: malformed,
      territory: "FI"
    )
    let index = Data(
      "<TrustServiceStatusList>\(pointer)</TrustServiceStatusList>".utf8
    )

    #expect(throws: EuTrustedListDirectory.Failure.unusableResponse) {
      try EuTrustedListDirectory.trustedListPointers(in: index)
    }
  }

  /// The frozen post-withdrawal UK list is authenticated metadata but
  /// is not a current EU/EEA member whose staleness makes the walk fail.
  @Test
  internal func historicalUkPointerIsExcluded() throws {
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    let current = Self.pointer(
      location: "https://example.test/fi.xml",
      certificate: signer.certificate,
      territory: "FI"
    )
    let historical = Self.pointer(
      location: "https://example.test/Final_EU_TSL-UKsigned.xml",
      certificate: signer.certificate,
      territory: "UK"
    )
    let index = Data(
      "<TrustServiceStatusList>\(current)\(historical)</TrustServiceStatusList>"
        .utf8
    )

    let pointers = try EuTrustedListDirectory.trustedListPointers(in: index)

    #expect(pointers.map(\.location) == ["https://example.test/fi.xml"])
  }

  /// The signer set is scoped to one exact authenticated location.
  @Test
  internal func conflictingSignerSetsForOneLocationAreRejected() throws {
    let first = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    let second = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    let firstPointer = Self.pointer(
      location: "https://example.test/list.xml",
      certificate: first.certificate,
      territory: "FI"
    )
    let secondPointer = Self.pointer(
      location: "https://example.test/list.xml",
      certificate: second.certificate,
      territory: "FI"
    )
    let index = Data(
      "<TrustServiceStatusList>\(firstPointer)\(secondPointer)</TrustServiceStatusList>"
        .utf8
    )

    #expect(throws: EuTrustedListDirectory.Failure.unusableResponse) {
      try EuTrustedListDirectory.trustedListPointers(in: index)
    }
  }
}
