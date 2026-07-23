/// The hash function of a FINEID signing algorithm reference.
///
/// Carried as the high nibble of the MSE:SET algorithm-reference byte
/// (FINEID S1 v4.2 §3.6.3 Table 6).
public enum SigningHash: Equatable, Sendable {
  /// SHA-224 (high nibble 3).
  case sha224

  /// SHA-256 (high nibble 4).
  case sha256

  /// SHA-384 (high nibble 5).
  case sha384

  /// SHA-512 (high nibble 6).
  case sha512

  /// The high nibble contributed to the algorithm-reference byte.
  internal var highNibble: UInt8 {
    switch self {
    case .sha224:
      FineidValues.hashNibbleSha224
    case .sha256:
      FineidValues.hashNibbleSha256
    case .sha384:
      FineidValues.hashNibbleSha384
    case .sha512:
      FineidValues.hashNibbleSha512
    }
  }
}
