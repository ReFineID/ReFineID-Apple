#if os(macOS)

  import CardCore
  import Foundation

  /// The qualified document-signing shape for each supported card key.
  extension CardKeyProfile {
    /// The exact card request for a SHA-384 digest of CMS signed attributes.
    internal func qualifiedDocumentRequest(digest: Data) -> SignRequest? {
      let scheme: SigningScheme
      switch self {
      case .ecdsaP384:
        scheme = .ecdsa
      case .rsa2048, .rsa3072:
        scheme = .rsaPkcs1
      }
      return SignRequest.resolve(
        profile: self,
        algorithm: SigningAlgorithm(hash: .sha384, scheme: scheme),
        digest: digest
      )
    }
  }

#endif
