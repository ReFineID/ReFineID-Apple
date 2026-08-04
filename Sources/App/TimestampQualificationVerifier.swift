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
      /// The service answered "not right now": rate limited, timing
      /// out, or failing. Something is there and said so itself, but
      /// the test could not run.
      case busy

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

    /// HTTP 408 Request Timeout.
    private static let requestTimeoutStatus = 408

    /// HTTP 429 Too Many Requests.
    private static let tooManyRequestsStatus = 429

    /// Where the client-error statuses begin.
    private static let clientErrorFloor = 400

    /// Where the server-error statuses begin.
    private static let serverErrorFloor = 500

    /// Where the statuses HTTP defines end; anything past this is
    /// not HTTP any more.
    private static let statusCeiling = 600

    /// Statuses meaning "who are you", which a commercial timestamp
    /// service answers without credentials.
    private static let credentialStatuses: Set<Int> = [
      Self.unauthorizedStatus,
      Self.forbiddenStatus,
      Self.proxyAuthenticationStatus,
    ]

    /// Statuses meaning "not right now".
    private static let busyStatuses: Set<Int> = [
      Self.requestTimeoutStatus,
      Self.tooManyRequestsStatus,
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
    /// Condemnation needs positive evidence, so it is allowlisted:
    /// the failures named here prove the host answered with something
    /// that is not a timestamp. Every other failure - and every
    /// failure this code has never heard of, which is why the default
    /// exists - decides nothing, because silence, a refused login, a
    /// rate limit, a server error, and a proper TSP rejection are all
    /// consistent with a real service. The costly mistake would be
    /// branding a real authority "not a time-stamp service"; an
    /// undecided verdict costs nothing, since it changes nothing.
    private static func classify(_ error: Error) -> Verdict {
      switch error {
      case SigningNetwork.Failure.httpStatus(let status):
        Self.classify(status: status)
      case SigningNetwork.Failure.unusableBody,
        RfcTimestamp.TokenFailure.malformed,
        RfcTimestamp.TokenFailure.imprintMismatch,
        RfcTimestamp.TokenFailure.nonceMismatch:
        .notTimestampService
      default:
        .undecided
      }
    }

    /// What one HTTP status says about the address.
    ///
    /// Only a client error condemns, and not one that speaks about
    /// the requester rather than the address. "Not right now" and
    /// the server-error class answer busy - a real service having a
    /// bad day says exactly that. Anything else decides nothing,
    /// including a status outside the classes HTTP defines: a 666
    /// proves only that something strange answered, and strange is
    /// not a verdict.
    private static func classify(status: Int) -> Verdict {
      if Self.busyStatuses.contains(status)
        || (Self.serverErrorFloor..<Self.statusCeiling).contains(status)
      {
        return .busy
      }
      guard
        (Self.clientErrorFloor..<Self.serverErrorFloor).contains(status)
      else { return .undecided }
      return Self.credentialStatuses.contains(status)
        ? .undecided : .notTimestampService
    }
  }

#endif
