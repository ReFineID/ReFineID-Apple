/// The signature scheme of a FINEID signing algorithm reference.
///
/// Carried as the low nibble of the MSE:SET algorithm-reference byte.
public enum SigningScheme: Equatable, Sendable {
  /// ECDSA (low nibble 4).
  case ecdsa

  /// RSASSA-PKCS1-v1_5 (low nibble 2).
  case rsaPkcs1

  /// The low nibble contributed to the algorithm-reference byte.
  internal var lowNibble: UInt8 {
    switch self {
    case .ecdsa:
      FineidValues.schemeNibbleEcdsa
    case .rsaPkcs1:
      FineidValues.schemeNibbleRsaPkcs1
    }
  }
}
