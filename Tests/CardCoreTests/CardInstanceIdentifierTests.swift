import CardCore
import Foundation
import Testing

@Suite
internal struct CardInstanceIdentifierTests {
  /// An ATR-shaped byte string standing in for a card's answer to reset.
  ///
  /// Only its bytes matter here: the derivation is a digest, so any fixed
  /// input pins it as well as a card's own would.
  private static let sampleAtrHexDigits = "3B7F9600008031B865B0850300EF120FFF829000"

  /// A second ATR-shaped byte string, differing from the first in one bit.
  ///
  /// Stands for the other interface of the same card, whose ATR differs
  /// and which must therefore never share an identifier with it.
  private static let otherAtrHexDigits = "3A7F9600008031B865B0850300EF120FFF829000"

  /// SHA-256 of `sampleAtrHexDigits`, computed independently with
  /// `shasum -a 256` rather than with the code under test.
  private static let sampleAtrDigestHex =
    "006c92fbe394971552634de8625267aa19876dee33d207b7abcd53e19a21764e"

  /// Certificate-shaped bytes standing in for a leaf DER.
  private static let sampleCertificateHexDigits = "308201223081C9A00302010202085AB1"

  /// SHA-256 of `sampleCertificateHexDigits`, computed independently with
  /// `shasum -a 256`.
  private static let sampleCertificateDigestHex =
    "17c2e7240f198eacf9452b78bbfee43ffc2d93e4774dc573ca100c4eee4f3f11"

  /// The instance id the contact path has always published: the first
  /// sixteen hex digits of the leaf digest, a dot, and the contents
  /// version.
  ///
  /// Spelled out rather than assembled from the type's own parts, so that
  /// a change to the derivation fails here instead of agreeing with
  /// itself. `ctkd` caches a token's published keychain contents under
  /// this string, so moving it silently re-mints every card already known
  /// to the system.
  private static let expectedCertificateIdentifier = "17c2e7240f198eac.2"

  @Test
  internal func refusesAnEmptyAnswerToReset() {
    #expect(CardInstanceIdentifier(answerToReset: Data()) == nil)
  }

  @Test
  internal func refusesAnEmptyCertificate() {
    #expect(CardInstanceIdentifier(authenticationCertificate: Data()) == nil)
  }

  @Test
  internal func derivesTheDigestOfTheAnswerToReset() throws {
    let atr = WireHex.data(Self.sampleAtrHexDigits)
    let identifier = try #require(CardInstanceIdentifier(answerToReset: atr))
    #expect(identifier.value.hasPrefix(Self.sampleAtrDigestHex))
  }

  @Test
  internal func carriesTheContentsVersionAsASuffix() throws {
    let atr = WireHex.data(Self.sampleAtrHexDigits)
    let identifier = try #require(CardInstanceIdentifier(answerToReset: atr))
    #expect(identifier.value.hasSuffix(CardInstanceIdentifier.contentsVersion))
    #expect(identifier.value.count > Self.sampleAtrDigestHex.count)
  }

  @Test
  internal func isDeterministicForTheSameCard() throws {
    let atr = WireHex.data(Self.sampleAtrHexDigits)
    let first = try #require(CardInstanceIdentifier(answerToReset: atr))
    let second = try #require(CardInstanceIdentifier(answerToReset: atr))
    #expect(first == second)
  }

  @Test
  internal func differsWhenTheAnswerToResetDiffers() throws {
    let contact = try #require(
      CardInstanceIdentifier(answerToReset: WireHex.data(Self.sampleAtrHexDigits)))
    let contactless = try #require(
      CardInstanceIdentifier(answerToReset: WireHex.data(Self.otherAtrHexDigits)))
    #expect(contact != contactless)
  }

  @Test
  internal func theContactIdentifierIsExactlyWhatItAlwaysWas() throws {
    // The wire fact of the contact path: the token extension published
    // this string before the contactless work, and a card already known
    // to ctkd must keep it.
    let identifier = try #require(
      CardInstanceIdentifier(
        authenticationCertificate: WireHex.data(Self.sampleCertificateHexDigits)))
    #expect(identifier.value == Self.expectedCertificateIdentifier)
  }

  @Test
  internal func theCertificateIdentifierKeepsOnlyTheDigestPrefix() throws {
    let identifier = try #require(
      CardInstanceIdentifier(
        authenticationCertificate: WireHex.data(Self.sampleCertificateHexDigits)))
    let digestPart = try #require(identifier.value.split(separator: ".").first)
    #expect(Self.sampleCertificateDigestHex.hasPrefix(digestPart))
    #expect(digestPart.count < Self.sampleCertificateDigestHex.count)
  }

  @Test
  internal func bothDerivationsCarryTheSameContentsVersion() throws {
    // One constant governs both transports; a bump that reached only one
    // of them would leave half the cards serving ctkd's cached contents.
    let fromAtr = try #require(
      CardInstanceIdentifier(answerToReset: WireHex.data(Self.sampleAtrHexDigits)))
    let fromCertificate = try #require(
      CardInstanceIdentifier(
        authenticationCertificate: WireHex.data(Self.sampleCertificateHexDigits)))
    let suffix = "." + CardInstanceIdentifier.contentsVersion
    #expect(fromAtr.value.hasSuffix(suffix))
    #expect(fromCertificate.value.hasSuffix(suffix))
  }
}
