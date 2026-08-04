import Foundation
import Testing

@testable import ReFineID

/// Direct checks for national service identities and cache boundaries.
@Suite
internal struct EuTrustedListCertificateTests {
  /// The ETSI containers a service must sit in to be covered by the
  /// list signature.
  private static let opening =
    "<TrustServiceStatusList><TrustServiceProviderList>"
    + "<TrustServiceProvider><TSPServices>"

  /// Their closing halves.
  private static let closing =
    "</TSPServices></TrustServiceProvider>"
    + "</TrustServiceProviderList></TrustServiceStatusList>"

  /// Only the current identity of a granted QTST service contributes;
  /// history and other service types must not become trust anchors.
  @Test
  internal func onlyCurrentGrantedQualifiedTimestampCertificatesAreReturned()
    throws
  {
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    let current = signer.certificate
    let history = Data("historical-certificate".utf8)
    let withdrawn = Data("withdrawn-certificate".utf8)
    let otherType = Data("other-service-certificate".utf8)
    let list = Data(
      """
      \(Self.opening)
        <TSPService>
          <ServiceInformation>
            <ServiceTypeIdentifier>http://uri.etsi.org/TrstSvc/Svctype/TSA/QTST</ServiceTypeIdentifier>
            <ServiceStatus>http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted</ServiceStatus>
            <ServiceDigitalIdentity>
              <X509Certificate>\(current.base64EncodedString())</X509Certificate>
            </ServiceDigitalIdentity>
          </ServiceInformation>
          <ServiceHistory>
            <ServiceHistoryInstance>
              <ServiceDigitalIdentity>
                <X509Certificate>\(history.base64EncodedString())</X509Certificate>
              </ServiceDigitalIdentity>
            </ServiceHistoryInstance>
          </ServiceHistory>
        </TSPService>
        <TSPService>
          <ServiceInformation>
            <ServiceTypeIdentifier>http://uri.etsi.org/TrstSvc/Svctype/TSA/QTST</ServiceTypeIdentifier>
            <ServiceStatus>http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/withdrawn</ServiceStatus>
            <ServiceDigitalIdentity>
              <X509Certificate>\(withdrawn.base64EncodedString())</X509Certificate>
            </ServiceDigitalIdentity>
          </ServiceInformation>
        </TSPService>
        <TSPService>
          <ServiceInformation>
            <ServiceTypeIdentifier>http://uri.etsi.org/TrstSvc/Svctype/TSA/TSA</ServiceTypeIdentifier>
            <ServiceStatus>http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted</ServiceStatus>
            <ServiceDigitalIdentity>
              <X509Certificate>\(otherType.base64EncodedString())</X509Certificate>
            </ServiceDigitalIdentity>
          </ServiceInformation>
        </TSPService>
      \(Self.closing)
      """.utf8
    )

    let found = try EuTrustedListDirectory.qualifiedTimestampCertificates(
      in: list
    )

    #expect(found == [current])
  }

  /// One malformed identity makes its signed national list unusable,
  /// preventing a bad value from poisoning the global anchor array.
  @Test
  internal func malformedGrantedQualifiedTimestampCertificateIsRejected()
    throws
  {
    let malformed = Data("not an X.509 certificate".utf8)
    let list = Data(
      """
      \(Self.opening)
        <TSPService>
          <ServiceInformation>
            <ServiceTypeIdentifier>http://uri.etsi.org/TrstSvc/Svctype/TSA/QTST</ServiceTypeIdentifier>
            <ServiceStatus>http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted</ServiceStatus>
            <ServiceDigitalIdentity>
              <X509Certificate>\(malformed.base64EncodedString())</X509Certificate>
            </ServiceDigitalIdentity>
          </ServiceInformation>
        </TSPService>
      \(Self.closing)
      """.utf8
    )

    #expect(throws: EuTrustedListDirectory.Failure.unusableResponse) {
      try EuTrustedListDirectory.qualifiedTimestampCertificates(in: list)
    }
  }

  /// A qualifying current service without an X.509 identity would make
  /// a complete directory capable of a false-negative decision.
  @Test
  internal func grantedQualifiedTimestampServiceWithoutCertificateIsRejected()
    throws
  {
    let list = Data(
      """
      \(Self.opening)
        <TSPService>
          <ServiceInformation>
            <ServiceTypeIdentifier>http://uri.etsi.org/TrstSvc/Svctype/TSA/QTST</ServiceTypeIdentifier>
            <ServiceStatus>http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted</ServiceStatus>
            <ServiceDigitalIdentity/>
          </ServiceInformation>
        </TSPService>
      \(Self.closing)
      """.utf8
    )

    #expect(throws: EuTrustedListDirectory.Failure.unusableResponse) {
      try EuTrustedListDirectory.qualifiedTimestampCertificates(in: list)
    }
  }

  /// A national list may legitimately have no currently granted QTST
  /// service; that is distinct from a qualifying service lacking identity.
  @Test
  internal func listWithoutQualifiedTimestampServicesIsValidAndEmpty() throws {
    let list = Data("<TrustServiceStatusList/>".utf8)

    let found = try EuTrustedListDirectory.qualifiedTimestampCertificates(
      in: list
    )

    #expect(found.isEmpty)
  }

  /// A remote list cannot turn an external entity into an address or
  /// certificate read from the local machine.
  @Test
  internal func externalXmlEntitiesAreNeverLoaded() throws {
    let index = Data(
      """
      <!DOCTYPE list [
        <!ENTITY external SYSTEM "file:///etc/hosts">
      ]>
      <TrustServiceStatusList>
        <SchemeInformation><PointersToOtherTSL>
        <OtherTSLPointer><TSLLocation>&external;</TSLLocation></OtherTSLPointer>
        </PointersToOtherTSL></SchemeInformation>
      </TrustServiceStatusList>
      """.utf8
    )

    #expect(throws: EuTrustedListDirectory.Failure.unusableResponse) {
      try EuTrustedListDirectory.trustedListPointers(in: index)
    }
  }

  /// Cache reuse ends at the earlier of its local and signed boundaries.
  @Test
  internal func cacheReuseHonorsBothExactExpiryBoundaries() {
    let fetchedAt = Date(timeIntervalSince1970: 1_000_000)
    let distantExpiry = fetchedAt.addingTimeInterval(7_200)
    let earlyExpiry = fetchedAt.addingTimeInterval(600)

    #expect(
      EuTrustedListDirectory.mayReuse(
        fetchedAt: fetchedAt,
        validUntil: distantExpiry,
        at: fetchedAt.addingTimeInterval(3_599)
      )
    )
    #expect(
      !EuTrustedListDirectory.mayReuse(
        fetchedAt: fetchedAt,
        validUntil: distantExpiry,
        at: fetchedAt.addingTimeInterval(3_600)
      )
    )
    #expect(
      !EuTrustedListDirectory.mayReuse(
        fetchedAt: fetchedAt,
        validUntil: earlyExpiry,
        at: earlyExpiry
      )
    )
    #expect(
      EuTrustedListDirectory.isCacheable(
        .init(certificates: [], isComplete: true)
      )
    )
    #expect(
      !EuTrustedListDirectory.isCacheable(
        .init(certificates: [], isComplete: false)
      )
    )
  }
}
