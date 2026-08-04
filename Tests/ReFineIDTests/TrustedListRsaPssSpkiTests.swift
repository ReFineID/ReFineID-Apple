import CardCore
import Foundation
import Security
import Testing

@testable import ReFineID

/// Direct checks for the narrowly gated restricted RSA-PSS SPKI workaround.
@Suite
internal struct TrustedListRsaPssSpkiTests {
  /// Germany's current restricted SPKI is imported only for fixed SHA-256 PSS.
  @Test
  internal func absentParametersVerifyFixedPss() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaPssSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(
      for: profile,
      certificateProfile: .valid,
      subjectPublicKeyProfile: .rsaPssAbsentParameters
    )
    let extracted = CertificateFacts.rsaPssPublicKeyWithAbsentParameters(
      der: signer.certificate
    )
    #expect(extracted != nil)
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
  }

  /// The stripped restricted-SPKI key is never used for other XML methods.
  @Test
  internal func fallbackIsFixedMethodOnly() throws {
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(
      for: .rsaPssSha256,
      certificateProfile: .valid,
      subjectPublicKeyProfile: .rsaPssAbsentParameters
    )
    let incompatibleProfiles: [TrustedListXmlSignatureFixtures.Profile] = [
      .rsaPssSha256Parameterized,
      .rsaSha256,
      .rsaSha512,
    ]
    for profile in incompatibleProfiles {
      let list = try TrustedListXmlSignatureFixtures.signedList(
        profile: profile,
        signer: signer,
        window: .current,
        schemeContent: ""
      )
      #expect(throws: TrustedListXmlSignature.Failure.invalidSignature) {
        try TrustedListXmlSignature.verify(
          list,
          trusting: .certificates([signer.certificate]),
          at: TrustedListXmlSignatureFixtures.validationTime
        )
      }
    }
  }

  /// Only absent PSS parameters and a byte-aligned canonical key are accepted.
  @Test
  internal func extractorRejectsOtherShapes() throws {
    let invalidProfiles: [TrustedListXmlSignatureFixtures.SubjectPublicKeyProfile] = [
      .rsaEncryption,
      .rsaPssEmptyParameters,
      .rsaPssIntegerParameter,
      .rsaPssNullParameters,
      .rsaPssUnusedBits,
    ]
    for subjectPublicKeyProfile in invalidProfiles {
      let signer = try TrustedListXmlSignatureFixtures.makeUncheckedSigner(
        for: .rsaPssSha256,
        subjectPublicKeyProfile: subjectPublicKeyProfile
      )
      #expect(
        CertificateFacts.rsaPssPublicKeyWithAbsentParameters(
          der: signer.certificate
        ) == nil
      )
    }
    #expect(
      CertificateFacts.rsaPssPublicKeyWithAbsentParameters(
        der: Data([0])
      ) == nil
    )
  }

  /// rsaEncryption certificates continue through Security's normal key path.
  @Test
  internal func ordinaryRsaUsesNormalSecurityImport() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaPssSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let certificate = try #require(
      SecCertificateCreateWithData(nil, signer.certificate as CFData)
    )
    #expect(SecCertificateCopyKey(certificate) != nil)
    #expect(
      CertificateFacts.rsaPssPublicKeyWithAbsentParameters(
        der: signer.certificate
      ) == nil
    )
    let list = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )
    _ = try TrustedListXmlSignature.verify(
      list,
      trusting: .certificates([signer.certificate]),
      at: TrustedListXmlSignatureFixtures.validationTime
    )
  }
}
