import Foundation
import Testing

@testable import ReFineID

/// The attack the enveloped-signature transform invites, from both
/// ends.
///
/// XMLDSig's enveloped transform removes the whole `ds:Signature`
/// element from the bytes the digest covers. Anything spliced in
/// there is therefore signed by nothing, while the list around it
/// still verifies bit for bit - so a reader that searches the whole
/// document reads unsigned data as though the signature vouched for
/// it. Two defences, tested here: the signature may carry nothing
/// outside its profile, and every reader anchors at the root through
/// child steps only.
@Suite
internal struct TrustedListWrappingTests {
  /// A qualified time-stamp service naming one certificate.
  private static func service(certificate: String) -> String {
    """
    <TSPService>
      <ServiceInformation>
        <ServiceTypeIdentifier>http://uri.etsi.org/TrstSvc/Svctype/TSA/QTST</ServiceTypeIdentifier>
        <ServiceStatus>http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted</ServiceStatus>
        <ServiceDigitalIdentity>
          <DigitalId><X509Certificate>\(certificate)</X509Certificate></DigitalId>
        </ServiceDigitalIdentity>
      </ServiceInformation>
    </TSPService>
    """
  }

  /// One pointer to a national list, with its pinned signer.
  private static func pointer(certificate: String) -> String {
    """
    <OtherTSLPointer>
      <ServiceDigitalIdentities>
        <ServiceDigitalIdentity>
          <DigitalId><X509Certificate>\(certificate)</X509Certificate></DigitalId>
        </ServiceDigitalIdentity>
      </ServiceDigitalIdentities>
      <TSLLocation>https://attacker.test/spliced.xml</TSLLocation>
      <AdditionalInformation>
        <OtherInformation><SchemeTerritory>FI</SchemeTerritory></OtherInformation>
        <OtherInformation><MimeType>application/vnd.etsi.tsl+xml</MimeType></OtherInformation>
      </AdditionalInformation>
    </OtherTSLPointer>
    """
  }

  /// Splices content into the signature element of a signed list,
  /// exactly as an attacker holding a genuine list would.
  private static func splicingIntoSignature(
    _ payload: String,
    of list: Data
  ) throws -> Data {
    let text = try #require(String(data: list, encoding: .utf8))
    let closing = "</ds:Signature>"
    let opening = try #require(text.range(of: closing))
    return Data(
      text.replacingCharacters(
        in: opening,
        with: "<ds:Object>\(payload)</ds:Object>\(closing)"
      ).utf8
    )
  }

  /// A genuine, correctly signed list.
  private static func signedList() throws -> (
    document: Data, certificate: Data
  ) {
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: .rsaSha256)
    return (
      try TrustedListXmlSignatureFixtures.signedList(
        profile: .rsaSha256,
        signer: signer,
        window: .current,
        schemeContent: ""
      ),
      signer.certificate
    )
  }

  /// A service hidden in the signature is refused outright, rather
  /// than verified and then read.
  @Test
  internal func aServiceSplicedIntoTheSignatureIsRefused() throws {
    let genuine = try Self.signedList()
    let attacker = Data("attacker-timestamp-certificate".utf8)
    let spliced = try Self.splicingIntoSignature(
      Self.service(certificate: attacker.base64EncodedString()),
      of: genuine.document
    )

    #expect(throws: TrustedListXmlSignature.Failure.wrapping) {
      try TrustedListXmlSignature.verify(
        spliced,
        trusting: .certificates([genuine.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// The same for a pointer, which would otherwise name both the
  /// national list to fetch and the certificate said to have signed
  /// it.
  @Test
  internal func aPointerSplicedIntoTheSignatureIsRefused() throws {
    let genuine = try Self.signedList()
    let attacker = Data("attacker-list-signer".utf8)
    let spliced = try Self.splicingIntoSignature(
      Self.pointer(certificate: attacker.base64EncodedString()),
      of: genuine.document
    )

    #expect(throws: TrustedListXmlSignature.Failure.wrapping) {
      try TrustedListXmlSignature.verify(
        spliced,
        trusting: .certificates([genuine.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// The second defence, standing alone: even handed a document whose
  /// signature was never checked, the readers see only what the
  /// signature could have covered.
  @Test
  internal func readersIgnoreWhatLivesInsideTheSignature() throws {
    let attacker = Data("attacker-timestamp-certificate".utf8)
    let hidden = Data(
      """
      <TrustServiceStatusList xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
        <ds:Signature>
          <ds:Object>
            \(Self.service(certificate: attacker.base64EncodedString()))
            \(Self.pointer(certificate: attacker.base64EncodedString()))
          </ds:Object>
        </ds:Signature>
      </TrustServiceStatusList>
      """.utf8
    )

    let certificates = try EuTrustedListDirectory.qualifiedTimestampCertificates(
      in: hidden
    )
    let pointers = try EuTrustedListDirectory.trustedListPointers(in: hidden)

    #expect(certificates.isEmpty)
    #expect(pointers.isEmpty)
  }
}
