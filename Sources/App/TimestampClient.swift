#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation

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
    }

    /// The content type RFC 3161 defines for a request.
    private static let requestContentType = "application/timestamp-query"

    /// One token over `digest`, from the first authority that answers.
    internal static func token(over digest: Data) async throws -> Data {
      let authorities = TimestampAuthorityStore.load()
      guard !authorities.isEmpty else {
        throw Failure.noAuthorityConfigured
      }
      var declined: [String] = []
      for authority in authorities {
        do {
          return try await Self.token(over: digest, from: authority)
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
    internal static func probeToken(from authority: String) async throws -> Data {
      var seed = Data(count: OcspRequest.nonceByteCount)
      seed.withUnsafeMutableBytes { buffer in
        if let base = buffer.baseAddress {
          _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
      }
      return try await Self.token(over: Data(SHA384.hash(data: seed)), from: authority)
    }

    /// One token from one authority, checked before it is accepted.
    private static func token(
      over digest: Data,
      from authority: String
    ) async throws -> Data {
      var nonce = Data(count: OcspRequest.nonceByteCount)
      nonce.withUnsafeMutableBytes { buffer in
        if let base = buffer.baseAddress {
          _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
      }
      let request = RfcTimestamp.request(digest: digest, nonceBytes: nonce)
      let credentials = TimestampAuthorityStore.credentials(for: authority)
      let response = try await SigningNetwork.post(
        request,
        to: authority,
        contentType: Self.requestContentType,
        credentials: credentials
      )
      return try RfcTimestamp.token(
        fromResponse: response, digest: digest, nonceBytes: nonce
      )
    }
  }

#endif
