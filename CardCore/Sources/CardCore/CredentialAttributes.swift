import Foundation

/// Parses the GET DATA PIN-container response
/// (FINEID S1 v4.2 §3.15.3 Table 19).
///
/// The container is flat, so the retries counter is found by scanning
/// for the `DF 21 04 tries ...` attributes object - the same
/// sliding-window approach the reference implementation uses; no BER
/// recursion is needed or wanted here.
public enum CredentialAttributes {
  /// The number of bytes in one attributes tag-length-value window:
  /// two tag bytes, one length byte, four attribute bytes.
  private static let attributesWindowLength: Int = 7

  /// Offset of the length byte inside the window: past the two tag
  /// bytes.
  private static let lengthOffset: Int = 2

  /// Offset of the retries byte inside the window: past the two tag
  /// bytes and the length byte.
  private static let triesOffset: Int = 3

  /// Extracts the retries-remaining counter, or nil when the body
  /// carries no parseable attributes object.
  public static func retryCounter(fromResponseBody body: Data) -> RetryCount? {
    let bytes = Array(body)
    guard bytes.count >= Self.attributesWindowLength else { return nil }
    for start in 0...(bytes.count - Self.attributesWindowLength) {
      guard
        bytes[start] == FineidValues.pinAttributesTagHigh,
        bytes[start + 1] == FineidValues.pinAttributesTagLow,
        bytes[start + Self.lengthOffset] == FineidValues.pinAttributesLength
      else {
        continue
      }
      return RetryCount(attemptsRemaining: bytes[start + Self.triesOffset])
    }
    return nil
  }
}
