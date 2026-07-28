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

  /// The exact PSO:CDS `Le` when it fits a short APDU.
  ///
  /// P-384 uses 96 to avoid a destructive `6Cxx` correction. RSA-3072
  /// leaves this nil and uses the maximum-length structured CTK path.
  internal let expectedSignatureLength: ExpectedResponseLength?

  /// Exact raw card result size for this key profile.
  internal let rawSignatureLength: Int

  /// The SecKey algorithm for verifying the re-encoded signature.
  ///
  /// ECDSA is hash-agnostic, so this is always the digest form matching
  /// `digest` - the card signs the bytes we loaded, and the token checks
  /// them against the leaf's public key before trusting the result.
  internal let verifyAlgorithm: SecKeyAlgorithm

  /// Converts the card result to the form Security.framework expects.
  ///
  /// ECDSA cards return `r || s` and CTK expects X9.62 DER. RSA cards
  /// already return their modulus-wide wire signature unchanged.
  internal func wireSignature(from raw: Data) -> Data? {
    guard raw.count == rawSignatureLength else { return nil }
    switch algorithm.scheme {
    case .ecdsa:
      return EcdsaSignature.derFromRawConcatenation(raw)
    case .rsaPkcs1, .rsaPss:
      return raw
    }
  }

  /// Whether `der` really is this request's signature under `publicKey`.
  ///
  /// The G4E card can sign silently-wrong bytes if the loaded hash was
  /// lost (S1 v4.2 §3.8.1.1). The exact-`Le` PSO:CDS prevents the known
  /// trigger, but checking here fails closed on any residual card fault
  /// rather than returning garbage that breaks the handshake opaquely -
  /// and matches the reference implementation's verify-before-return.
  /// Both transports check; the check is local, so it costs no field.
  internal func isSatisfied(by signature: Data, from publicKey: SecKey) -> Bool {
    var error: Unmanaged<CFError>?
    return SecKeyVerifySignature(
      publicKey,
      verifyAlgorithm,
      digest as CFData,
      signature as CFData,
      &error
    )
  }
}
