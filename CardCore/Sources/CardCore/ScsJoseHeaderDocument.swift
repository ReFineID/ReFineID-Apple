import Foundation

/// A compact JWS protected header, as far as this service reads it
/// (DVV SCS specification v1.3 §2.7; RFC 7515).
internal struct ScsJoseHeaderDocument: Codable {
  /// The JWS algorithm name.
  internal let alg: String
}
