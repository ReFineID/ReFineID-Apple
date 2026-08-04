import CryptoKit
import Foundation
import Testing

@testable import ReFineID

/// Direct cryptographic and structural tests for trusted-list XMLDSig.
@Suite
internal struct TrustedListXmlSignatureTests {
  /// Replaces one required fixture substring.
  private static func replacing(
    _ original: String,
    with replacement: String,
    in encoded: Data
  ) -> Data {
    guard let text = String(data: encoded, encoding: .utf8) else {
      return encoded
    }
    return Data(text.replacingOccurrences(of: original, with: replacement).utf8)
  }

  /// Flips one base64 character inside a named element's text.
  private static func changingFirstValueCharacter(
    of element: String,
    in encoded: Data
  ) -> Data {
    guard var text = String(data: encoded, encoding: .utf8) else {
      return encoded
    }
    let marker = "<\(element)>"
    guard let opening = text.range(of: marker), opening.upperBound < text.endIndex
    else {
      return encoded
    }
    let index = opening.upperBound
    text.replaceSubrange(index...index, with: text[index] == "A" ? "B" : "A")
    return Data(text.utf8)
  }

  /// Every explicitly supported signing profile verifies end to end.
  @Test
  internal func supportedSignatureProfilesVerify() throws {
    for profile in TrustedListXmlSignatureFixtures.Profile.allCases {
      let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
      let list = try TrustedListXmlSignatureFixtures.signedList(
        profile: profile,
        signer: signer,
        window: .current,
        schemeContent: ""
      )

      let verified = try TrustedListXmlSignature.verify(
        list,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )

      #expect(verified.signerCertificate == signer.certificate)
      #expect(verified.nextUpdate > verified.issuedAt)
    }
  }

  /// The LOTL trust mode accepts the exact published SHA-256 fingerprint.
  @Test
  internal func exactCertificateFingerprintAuthenticatesSigner() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha512
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let list = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )
    let fingerprint = Data(SHA256.hash(data: signer.certificate))

    let verified = try TrustedListXmlSignature.verify(
      list,
      trusting: .sha256Fingerprints([fingerprint]),
      at: TrustedListXmlSignatureFixtures.validationTime
    )

    #expect(verified.signerCertificate == signer.certificate)
  }

  /// A signed-document mutation is caught by its Reference digest.
  @Test
  internal func documentTamperIsRejected() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let signed = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )
    let tampered = Self.replacing(
      "<TSLSequenceNumber>1</TSLSequenceNumber>",
      with: "<TSLSequenceNumber>2</TSLSequenceNumber>",
      in: signed
    )

    #expect(throws: TrustedListXmlSignature.Failure.invalidDigest) {
      try TrustedListXmlSignature.verify(
        tampered,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// SignatureValue itself is verified, not merely its signed digests.
  @Test
  internal func signatureValueTamperIsRejected() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaPssSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let signed = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )
    let tampered = Self.changingFirstValueCharacter(
      of: "ds:SignatureValue",
      in: signed
    )

    #expect(throws: TrustedListXmlSignature.Failure.invalidSignature) {
      try TrustedListXmlSignature.verify(
        tampered,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// A valid signature cannot cross an authenticated pointer boundary.
  @Test
  internal func wrongSignerCertificateIsRejected() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let wrong = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let list = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )

    #expect(throws: TrustedListXmlSignature.Failure.untrustedSigner) {
      try TrustedListXmlSignature.verify(
        list,
        trusting: .certificates([wrong.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// A correctly signed list is unusable at and after NextUpdate.
  @Test
  internal func staleSignedListIsRejected() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha512
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let list = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .stale,
      schemeContent: ""
    )

    #expect(throws: TrustedListXmlSignature.Failure.stale) {
      try TrustedListXmlSignature.verify(
        list,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// The signed freshness interval is half-open at exact NextUpdate.
  @Test
  internal func exactNextUpdateBoundaryIsRejected() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha512
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let list = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )
    guard
      let nextUpdate = TrustedListXmlSignature.date(
        TrustedListXmlSignatureFixtures.Window.current.nextUpdate
      )
    else {
      Issue.record("Fixture NextUpdate must parse")
      return
    }

    #expect(throws: TrustedListXmlSignature.Failure.stale) {
      try TrustedListXmlSignature.verify(
        list,
        trusting: .certificates([signer.certificate]),
        at: nextUpdate
      )
    }
  }

  /// Duplicate same-document IDs are rejected before digest processing.
  @Test
  internal func duplicateIdWrappingIsRejected() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let signed = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )
    let wrapped = Self.replacing(
      "<TSLSequenceNumber>1</TSLSequenceNumber>",
      with: "<TSLSequenceNumber Id=\"properties\">1</TSLSequenceNumber>",
      in: signed
    )

    #expect(throws: TrustedListXmlSignature.Failure.wrapping) {
      try TrustedListXmlSignature.verify(
        wrapped,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// Transform chains outside the fixed ETSI profile fail closed.
  @Test
  internal func unsupportedReferenceTransformIsRejected() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let signed = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )
    let unsupported = Self.replacing(
      TrustedListXmlSignature.Xml.envelopedTransform,
      with: "http://www.w3.org/2000/09/xmldsig#base64",
      in: signed
    )

    #expect(throws: TrustedListXmlSignature.Failure.unsupportedAlgorithm) {
      try TrustedListXmlSignature.verify(
        unsupported,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }
}
