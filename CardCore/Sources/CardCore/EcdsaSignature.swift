import Foundation

/// Converts a card's raw ECDSA signature into X9.62 DER.
///
/// FINEID cards return an ECDSA signature as raw `r || s` (48 + 48 = 96
/// bytes for P-384; FINEID S1 v4.2 §3.8.3): two fixed-width big-endian
/// integers, no wrapper. The platform's `ecdsaSignatureDigestX962...`
/// algorithms expect the X9.62 form `SEQUENCE { INTEGER r, INTEGER s }`,
/// so the raw halves are re-encoded as DER integers here. This is the
/// one signature-shape adapter the minimal driver needs; it does no
/// cryptography.
public enum EcdsaSignature {
  /// DER tags used in the X9.62 signature structure.
  private static let sequenceTag: UInt8 = 0x30
  private static let integerTag: UInt8 = 0x02

  /// The high-bit mask that forces a leading zero on a DER integer.
  private static let highBitMask: UInt8 = 0x80

  /// The two equal halves of a raw ECDSA signature (`r` and `s`).
  private static let signatureHalves = 2

  /// Re-encodes raw `r || s` (an even-length buffer) as X9.62 DER, or
  /// nil when the input is empty or odd-length.
  public static func derFromRawConcatenation(_ raw: Data) -> Data? {
    let bytes = Array(raw)
    guard !bytes.isEmpty, bytes.count.isMultiple(of: Self.signatureHalves) else {
      return nil
    }
    let half = bytes.count / Self.signatureHalves
    let rInteger = derInteger(Array(bytes[0..<half]))
    let sInteger = derInteger(Array(bytes[half..<bytes.count]))
    var body = rInteger
    body.append(contentsOf: sInteger)
    var out: [UInt8] = [Self.sequenceTag]
    out.append(contentsOf: derLength(body.count))
    out.append(contentsOf: body)
    return Data(out)
  }

  /// Encodes one big-endian magnitude as a DER INTEGER: strip leading
  /// zeros, then prepend a single zero if the top bit is set (so the
  /// value stays positive).
  private static func derInteger(_ magnitude: [UInt8]) -> [UInt8] {
    var value = magnitude
    while value.count > 1, value.first == 0 {
      value.removeFirst()
    }
    if let first = value.first, first & Self.highBitMask != 0 {
      value.insert(0, at: 0)
    }
    var out: [UInt8] = [Self.integerTag]
    out.append(contentsOf: derLength(value.count))
    out.append(contentsOf: value)
    return out
  }

  /// Short- or long-form DER length for a signature-sized value.
  private static func derLength(_ length: Int) -> [UInt8] {
    let shortFormMaximum = 0x7F
    let oneLengthByteMarker: UInt8 = 0x81
    if length <= shortFormMaximum {
      return [UInt8(length)]
    }
    return [oneLengthByteMarker, UInt8(length)]
  }
}
