import CardCore
import CryptoKit
import Foundation
import Security

/// A resolved signature request: the card algorithm to select, the exact
/// digest to sign, the signature length the card will return, and the
/// algorithm to verify that signature against the leaf before trusting
/// it.
internal struct SignRequest {
  /// The MSE:SET algorithm to pin the card to.
  internal let algorithm: SigningAlgorithm

  /// The digest bytes to hand PSO:HASH.
  internal let digest: Data

  /// The exact length of the card's raw signature, sent as the PSO:CDS
  /// `Le` up front so the T=0 card never answers `6Cxx` (which can drop
  /// the loaded hash - S1 v4.2 §3.8.1.1).
  internal let expectedSignatureLength: ExpectedResponseLength

  /// The SecKey algorithm for verifying the re-encoded signature.
  ///
  /// ECDSA is hash-agnostic, so this is always the digest form matching
  /// `digest` - the card signs the bytes we loaded, and the token checks
  /// them against the leaf's public key before trusting the result.
  internal let verifyAlgorithm: SecKeyAlgorithm
}
