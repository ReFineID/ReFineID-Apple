import CardCore
import Testing

@testable import ReFineID

/// Direct checks for the evidence-to-verdict boundary shown in the
/// timestamp-authority settings table.
@Suite
internal struct TimestampQualificationVerifierTests {
  /// A cryptographically valid signer absent from a complete EU
  /// directory is a timestamp service, but not a qualified one.
  @Test
  internal func absentSignerIsNotQualified() {
    #expect(
      TimestampQualificationVerifier.classify(
        TimestampClient.Failure.signerNotQualified
      ) == .notQualified
    )
  }

  /// Incomplete trusted-list coverage cannot produce a legal status.
  @Test
  internal func incompleteDirectoryIsUndecided() {
    #expect(
      TimestampQualificationVerifier.classify(
        TimestampClient.Failure.qualificationUnavailable
      ) == .undecided
    )
  }

  /// A token whose CMS signature fails is not accepted as proof that
  /// the address runs a timestamp service.
  @Test
  internal func invalidCmsSignatureIsNotATimestampService() {
    #expect(
      TimestampQualificationVerifier.classify(
        TimestampTokenVerifier.Failure.invalidSignature
      ) == .notTimestampService
    )
  }

  /// HTTP errors distinguish transient service trouble, an unrelated
  /// endpoint, and a service that merely requires credentials.
  @Test
  internal func httpStatusesKeepTheirDistinctMeanings() {
    #expect(
      TimestampQualificationVerifier.classify(
        SigningNetwork.Failure.httpStatus(429)
      ) == .busy
    )
    #expect(
      TimestampQualificationVerifier.classify(
        SigningNetwork.Failure.httpStatus(503)
      ) == .busy
    )
    #expect(
      TimestampQualificationVerifier.classify(
        SigningNetwork.Failure.httpStatus(404)
      ) == .notTimestampService
    )
    #expect(
      TimestampQualificationVerifier.classify(
        SigningNetwork.Failure.httpStatus(401)
      ) == .undecided
    )
    #expect(
      TimestampQualificationVerifier.classify(
        SigningNetwork.Failure.httpStatus(666)
      ) == .undecided
    )
  }
}
