#if os(macOS)

  import CardCore
  import Foundation

  /// Tests whether a time-stamp authority is qualified for eIDAS use.
  ///
  /// Nothing here is anyone's claim. The service is asked for a real
  /// token, so it proves who it is by signing; whoever signed is then
  /// looked for among the granted qualified time-stamp services on
  /// the EU member states' trusted lists, which is where
  /// qualification is decided and nowhere else.
  internal enum TimestampQualificationVerifier {
    /// What the test concluded, or that it could not.
    internal enum Verdict {
      /// The signer was found nowhere on the trusted lists.
      case notQualified

      /// The address answered, but not with timestamps: an error
      /// status, an empty body, or bytes that are not a timestamp
      /// response. Whatever lives there, it is not this service.
      case notTimestampService

      /// The signer is a granted qualified service on a trusted list.
      case qualified

      /// Nothing conclusive: the host was silent, the request needed
      /// credentials, a real service declined this request, or the
      /// trusted lists were not readable. The stored mark is left
      /// alone rather than turned into a wrong answer.
      case undecided
    }

    /// HTTP 401 Unauthorized.
    private static let unauthorizedStatus = 401

    /// HTTP 403 Forbidden.
    private static let forbiddenStatus = 403

    /// HTTP 407 Proxy Authentication Required.
    private static let proxyAuthenticationStatus = 407

    /// Statuses meaning "who are you", which a commercial timestamp
    /// service answers without credentials.
    private static let credentialStatuses: Set<Int> = [
      Self.unauthorizedStatus,
      Self.forbiddenStatus,
      Self.proxyAuthenticationStatus,
    ]

    /// Asks the service to prove itself and the trusted lists to
    /// judge it.
    internal static func verdict(for authority: String) async -> Verdict {
      let token: Data
      do {
        token = try await TimestampClient.probeToken(from: authority)
      } catch {
        return Self.classify(error)
      }
      let chain = CmsCertificates.inside(token)
      guard !chain.isEmpty else { return .undecided }
      guard
        let identities =
          try? await EuTrustedListDirectory.qualifiedTimestampIdentities(),
        !identities.certificates.isEmpty
      else { return .undecided }
      if chain.contains(where: { identities.certificates.contains($0) }) {
        return .qualified
      }
      let keys = chain.compactMap { der in
        CertificateFacts(der: der)?.publicKeyBits
      }
      return keys.contains { identities.publicKeys.contains($0) }
        ? .qualified : .notQualified
    }

    /// What a failed probe says about the address.
    ///
    /// An answer that is not a timestamp - an error status, an empty
    /// body, bytes that do not parse - condemns the address; silence,
    /// a credentials refusal, and a proper TSP rejection do not,
    /// because each is consistent with a real service.
    private static func classify(_ error: Error) -> Verdict {
      switch error {
      case SigningNetwork.Failure.httpStatus(let status):
        Self.credentialStatuses.contains(status)
          ? .undecided : .notTimestampService
      case SigningNetwork.Failure.unusableBody,
        RfcTimestamp.TokenFailure.malformed,
        RfcTimestamp.TokenFailure.imprintMismatch,
        RfcTimestamp.TokenFailure.nonceMismatch:
        .notTimestampService
      default:
        .undecided
      }
    }
  }

#endif
