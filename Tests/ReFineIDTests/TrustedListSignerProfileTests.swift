import Foundation
import Testing

@testable import ReFineID

/// Direct signed-document checks for the TSL signer certificate profile.
@Suite
internal struct TrustedListSignerProfileTests {
  /// SignedProperties must name the exact certificate that verified the XML.
  @Test
  internal func xadesSignerCertificateDigestMustMatch() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha512
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let list = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: "",
      xadesBinding: .mismatched
    )

    #expect(throws: TrustedListXmlSignature.Failure.invalidSignerProfile) {
      try TrustedListXmlSignature.verify(
        list,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// SigningCertificateV2 is a required part of the signed XAdES profile.
  @Test
  internal func missingXadesSignerCertificateBindingIsRejected() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha512
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let list = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: "",
      xadesBinding: .omitted
    )

    #expect(throws: TrustedListXmlSignature.Failure.malformed) {
      try TrustedListXmlSignature.verify(
        list,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// The signer must have been valid at the signed list issue time.
  @Test
  internal func signerValidityIsCheckedAtSignedIssueTime() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(
      for: profile,
      certificateProfile: .expiredBeforeIssue
    )
    let list = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: ""
    )

    #expect(throws: TrustedListXmlSignature.Failure.invalidSignerProfile) {
      try TrustedListXmlSignature.verify(
        list,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }

  /// A TSL signer cannot assert CA=true or carry non-signing KeyUsage.
  @Test
  internal func signerCertificateProfileRejectsCaAndNonSigningUsage() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha256
    let invalidProfiles: [TrustedListXmlSignatureFixtures.CertificateProfile] = [
      .certificateAuthority,
      .nonSigningKeyUsage,
    ]
    for certificateProfile in invalidProfiles {
      let signer = try TrustedListXmlSignatureFixtures.makeSigner(
        for: profile,
        certificateProfile: certificateProfile
      )
      let list = try TrustedListXmlSignatureFixtures.signedList(
        profile: profile,
        signer: signer,
        window: .current,
        schemeContent: ""
      )

      #expect(throws: TrustedListXmlSignature.Failure.invalidSignerProfile) {
        try TrustedListXmlSignature.verify(
          list,
          trusting: .certificates([signer.certificate]),
          at: TrustedListXmlSignatureFixtures.validationTime
        )
      }
    }
  }

  /// Omitted BasicConstraints and KeyUsage retain their X.509 defaults.
  @Test
  internal func absentSignerCertificateConstraintsRemainCompatible() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha256
    let compatibleProfiles: [TrustedListXmlSignatureFixtures.CertificateProfile] = [
      .basicConstraintsAbsent,
      .endEntityPathLength,
      .keyUsageAbsent,
    ]
    for certificateProfile in compatibleProfiles {
      let signer = try TrustedListXmlSignatureFixtures.makeSigner(
        for: profile,
        certificateProfile: certificateProfile
      )
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
  }

  /// Six calendar months accepts exactly one hour of DST publication skew.
  @Test
  internal func freshnessHasExactOneHourDstTolerance() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha512
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let boundary = TrustedListXmlSignatureFixtures.Window(
      issuedAt: "2026-08-01T00:00:00Z",
      nextUpdate: "2027-02-01T01:00:00Z"
    )
    let beyond = TrustedListXmlSignatureFixtures.Window(
      issuedAt: boundary.issuedAt,
      nextUpdate: "2027-02-01T01:00:01Z"
    )
    let accepted = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: boundary,
      schemeContent: ""
    )
    let rejected = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: beyond,
      schemeContent: ""
    )

    _ = try TrustedListXmlSignature.verify(
      accepted,
      trusting: .certificates([signer.certificate]),
      at: TrustedListXmlSignatureFixtures.validationTime
    )
    #expect(throws: TrustedListXmlSignature.Failure.stale) {
      try TrustedListXmlSignature.verify(
        rejected,
        trusting: .certificates([signer.certificate]),
        at: TrustedListXmlSignatureFixtures.validationTime
      )
    }
  }
}
