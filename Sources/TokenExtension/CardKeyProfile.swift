import Foundation
import Security

/// The supported authentication-key profiles, resolved from a leaf
/// certificate's public key by the platform - CardCore never parses
/// X.509, and neither does this: `SecCertificateCopyKey` and
/// `SecKeyCopyAttributes` report the key facts.
///
/// Current Finnish cards carry one of these two on the authentication
/// slot; anything else is unsupported and the token is not created.
internal enum CardKeyProfile: Equatable {
  /// ECDSA P-384 (2026-generation cards).
  case ecdsaP384

  /// RSA 3072-bit (older production cards).
  case rsa3072

  /// RSA modulus size for the supported RSA profile.
  private static let rsaKeySizeInBits = 3_072

  /// EC field size for the supported ECC profile.
  private static let ecKeySizeInBits = 384

  /// Raw P-384 signature length: `r || s`, two 48-byte field elements.
  private static let ecdsaP384SignatureBytes = 96

  /// Raw RSA-3072 signature length: one modulus-wide block.
  private static let rsa3072SignatureBytes = 384

  /// The Security key type constant for this profile.
  internal var keyType: String {
    switch self {
    case .rsa3072:
      kSecAttrKeyTypeRSA as String
    case .ecdsaP384:
      kSecAttrKeyTypeECSECPrimeRandom as String
    }
  }

  /// The key size in bits.
  internal var keySizeInBits: Int {
    switch self {
    case .rsa3072:
      Self.rsaKeySizeInBits
    case .ecdsaP384:
      Self.ecKeySizeInBits
    }
  }

  /// The exact byte length of the card's raw signature for this key,
  /// sent as the PSO:CDS `Le` up front (S1 v4.2 §3.8.1.1 - a `6Cxx`
  /// length correction can drop the loaded hash on the T=0 card).
  internal var rawSignatureLength: Int {
    switch self {
    case .rsa3072:
      Self.rsa3072SignatureBytes
    case .ecdsaP384:
      Self.ecdsaP384SignatureBytes
    }
  }

  /// Resolves the profile from a leaf certificate's public key facts,
  /// or nil for an unsupported key.
  internal static func resolve(fromCertificate certificate: SecCertificate) -> Self? {
    guard
      let key = SecCertificateCopyKey(certificate),
      let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
      let certificateKeyType = attributes[kSecAttrKeyType] as? String,
      let keySize = attributes[kSecAttrKeySizeInBits] as? Int
    else {
      return nil
    }
    for profile in [Self.ecdsaP384, .rsa3072]
    where profile.keyType == certificateKeyType && profile.keySizeInBits == keySize {
      return profile
    }
    return nil
  }
}
