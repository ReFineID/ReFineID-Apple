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

      /// The signer is a granted qualified service on a trusted list.
      case qualified

      /// No token answered, or the trusted lists were not readable;
      /// the stored mark is left alone rather than turned into a
      /// wrong answer.
      case undecided
    }

    /// Asks the service to prove itself and the trusted lists to
    /// judge it.
    internal static func verdict(for authority: String) async -> Verdict {
      guard
        let token = try? await TimestampClient.probeToken(from: authority)
      else { return .undecided }
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
  }

#endif
