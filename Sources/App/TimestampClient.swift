#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation
  import Security

  /// Asks the configured authorities for a qualified timestamp.
  ///
  /// The order in Settings is the order asked, and the first authority
  /// to answer with a token that binds to the digest wins. Anything
  /// else about an authority - unreachable, refusing, answering with a
  /// token for someone else's digest - is a reason to try the next
  /// one, never a reason to accept less.
  internal enum TimestampClient {
    /// Why no token could be obtained.
    internal enum Failure: Error, Equatable {
      /// Every configured authority declined or failed.
      case noAuthorityAnswered([String])

      /// Settings has no authority to ask.
      case noAuthorityConfigured

      /// The EU directory could not prove either membership or
      /// complete absence.
      case qualificationUnavailable

      /// Secure random bytes for the request could not be made.
      case randomUnavailable

      /// A complete EU directory does not contain this signer.
      case signerNotQualified
    }

    /// The content type RFC 3161 defines for a request.
    private static let requestContentType = "application/timestamp-query"

    /// Entropy carried by each request nonce.
    private static let nonceByteCount = 32

    /// One token over `digest`, from the first authority that answers.
    internal static func token(
      over digest: Data
    ) async throws -> TimestampTokenVerifier.VerifiedToken {
      let authorities = TimestampAuthorityStore.load()
      guard !authorities.isEmpty else {
        throw Failure.noAuthorityConfigured
      }
      let identities = try await Self.trustedIdentities()
      var declined: [String] = []
      for authority in authorities {
        do {
          return try await Self.token(
            over: digest,
            from: authority,
            identities: identities
          )
        } catch {
          declined.append("\(authority): \(error)")
        }
      }
      throw Failure.noAuthorityAnswered(declined)
    }

    /// One token from one authority over a throwaway digest.
    ///
    /// The qualification test uses this to learn who signs at an
    /// address: the token's own certificates say so, bound to a
    /// digest that attests nothing.
    internal static func probeToken(
      from authority: String
    ) async throws -> TimestampTokenVerifier.VerifiedToken {
      let seed = try Self.randomBytes()
      return try await Self.token(
        over: Data(SHA384.hash(data: seed)),
        from: authority,
        identities: try await Self.trustedIdentities()
      )
    }

    /// One token from one authority, checked before it is accepted.
    private static func token(
      over digest: Data,
      from authority: String,
      identities: EuTrustedListDirectory.Identities
    ) async throws -> TimestampTokenVerifier.VerifiedToken {
      let nonce = try Self.randomBytes()
      let request = RfcTimestamp.request(digest: digest, nonceBytes: nonce)
      let credentials = TimestampAuthorityStore.credentials(for: authority)
      let response = try await SigningNetwork.post(
        request,
        to: authority,
        contentType: Self.requestContentType,
        credentials: credentials,
        endpoint: .authority
      )
      let token = try RfcTimestamp.token(
        fromResponse: response, digest: digest, nonceBytes: nonce
      )
      do {
        return try TimestampTokenVerifier.verify(
          token,
          trustedCertificates: Array(identities.certificates)
        )
      } catch TimestampTokenVerifier.Failure.untrustedSigner {
        throw identities.isComplete
          ? Failure.signerNotQualified : Failure.qualificationUnavailable
      }
    }

    /// One current directory result with at least one possible anchor.
    private static func trustedIdentities() async throws
      -> EuTrustedListDirectory.Identities
    {
      do {
        let identities =
          try await EuTrustedListDirectory
          .qualifiedTimestampIdentities()
        guard !identities.certificates.isEmpty else {
          throw Failure.qualificationUnavailable
        }
        return identities
      } catch let failure as Failure {
        throw failure
      } catch {
        throw Failure.qualificationUnavailable
      }
    }

    /// A fresh nonce, failing rather than sending zeros when the
    /// operating system's random source fails.
    private static func randomBytes() throws -> Data {
      var bytes = Data(count: Self.nonceByteCount)
      let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
        guard let base = buffer.baseAddress else { return errSecAllocate }
        return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
      }
      guard status == errSecSuccess else { throw Failure.randomUnavailable }
      return bytes
    }
  }

#endif
