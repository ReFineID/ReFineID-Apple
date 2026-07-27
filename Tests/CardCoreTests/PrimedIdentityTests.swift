import CardCore
import Foundation
import Testing

@Suite
internal struct PrimedIdentityTests {
  /// Six digits standing in for a card access number in tests only.
  private static let sampleCan = "123456"

  /// A short DER-shaped byte string standing in for a certificate.
  private static let sampleCertificateHexDigits = "3082000102030405"

  /// A different DER-shaped byte string, standing in for the issuer.
  private static let sampleIssuerHexDigits = "308200010A0B0C0D"

  /// A plausible PKCS#15 token serial.
  private static let sampleSerial = "6543210987654321"

  @Test
  internal func refusesACardAccessNumberThatIsNotSixDigits() {
    let certificate = WireHex.data(Self.sampleCertificateHexDigits)
    #expect(
      PrimedIdentity(can: "12345", certificate: certificate, issuer: nil, tokenSerial: nil) == nil)
    #expect(
      PrimedIdentity(can: "12345a", certificate: certificate, issuer: nil, tokenSerial: nil) == nil)
  }

  @Test
  internal func refusesAnEmptyCertificate() {
    #expect(
      PrimedIdentity(
        can: Self.sampleCan, certificate: Data(), issuer: nil, tokenSerial: nil) == nil)
  }

  @Test
  internal func refusesAnImplausibleSerial() {
    let certificate = WireHex.data(Self.sampleCertificateHexDigits)
    #expect(
      PrimedIdentity(
        can: Self.sampleCan, certificate: certificate, issuer: nil, tokenSerial: "") == nil)
  }

  @Test
  internal func acceptsAPrimeWithoutIssuerOrSerial() throws {
    let certificate = WireHex.data(Self.sampleCertificateHexDigits)
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan, certificate: certificate, issuer: nil, tokenSerial: nil))
    #expect(identity.issuerDER == nil)
    #expect(identity.tokenSerial == nil)
  }

  @Test
  internal func codingRoundTripPreservesEveryField() throws {
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: WireHex.data(Self.sampleIssuerHexDigits),
        tokenSerial: Self.sampleSerial))
    let payload = try JSONEncoder().encode(identity)
    let decoded = try JSONDecoder().decode(PrimedIdentity.self, from: payload)
    #expect(decoded == identity)
  }

  @Test
  internal func codingRoundTripPreservesAbsentOptionals() throws {
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: nil,
        tokenSerial: nil))
    let payload = try JSONEncoder().encode(identity)
    let decoded = try JSONDecoder().decode(PrimedIdentity.self, from: payload)
    #expect(decoded == identity)
    #expect(decoded.issuerDER == nil)
    #expect(decoded.tokenSerial == nil)
  }
}
