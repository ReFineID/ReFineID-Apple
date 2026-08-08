import CCryptoki
import Foundation

/// EC encoding translations between Security.framework and PKCS#11.
///
/// Security.framework hands out uncompressed SEC 1 points and X9.62 DER
/// signatures; PKCS#11 wants the named-curve OID in CKA_EC_PARAMS, the
/// point wrapped in a DER OCTET STRING in CKA_EC_POINT, and CKM_ECDSA
/// signatures as the raw r||s concatenation. Named protocol values come
/// from EcEncoding.h in the CCryptoki target.
package enum EcEncoding {
  /// Base of one DER length octet.
  private static let octetBase = 256

  /// An uncompressed point carries two coordinates; a raw signature
  /// carries two halves.
  private static let elementCount = 2

  /// DER long-form lengths beyond two octets never occur in the sizes
  /// the bridge handles and are rejected.
  private static let maximumLengthOctets = 2
  /// DER-encoded named-curve OID for a field width in bytes, or nil
  /// for an unsupported curve.
  package static func parameters(fieldWidth: Int) -> Data? {
    switch CK_ULONG(fieldWidth) {
    case EcFieldBytesP256:
      return withUnsafeBytes(of: EcParamsP256) { Data($0) }
    case EcFieldBytesP384:
      return withUnsafeBytes(of: EcParamsP384) { Data($0) }
    case EcFieldBytesP521:
      return withUnsafeBytes(of: EcParamsP521) { Data($0) }
    default:
      return nil
    }
  }

  /// Field width in bytes for an uncompressed SEC 1 point, or nil when
  /// the data is not one.
  package static func fieldWidth(uncompressedPoint point: Data) -> Int? {
    guard point.first == EcUncompressedPointTag, point.count % elementCount == 1
    else { return nil }
    let width = (point.count - 1) / elementCount
    guard parameters(fieldWidth: width) != nil else { return nil }
    return width
  }

  /// Wraps an uncompressed point in the DER OCTET STRING that
  /// CKA_EC_POINT carries.
  package static func wrappedPoint(_ point: Data) -> Data {
    Data([Asn1OctetStringTag]) + derLength(point.count) + point
  }

  /// Converts an X9.62 DER ECDSA signature into raw CKM_ECDSA form.
  ///
  /// Each half is left-padded to the field width. Returns nil when the
  /// DER is malformed or a half exceeds the width.
  package static func rawSignature(fromDer der: Data, fieldWidth: Int) -> Data? {
    let bytes = Data(der)
    var index = 0
    guard readByte(bytes, &index) == Asn1SequenceTag,
      let bodyLength = readLength(bytes, &index),
      bodyLength == bytes.count - index,
      let firstHalf = readInteger(bytes, &index),
      let secondHalf = readInteger(bytes, &index),
      index == bytes.count,
      let rPadded = padded(firstHalf, to: fieldWidth),
      let sPadded = padded(secondHalf, to: fieldWidth)
    else { return nil }
    return rPadded + sPadded
  }

  /// DER length octets for a content length.
  private static func derLength(_ count: Int) -> Data {
    let longFormThreshold = Int(Asn1LongFormLengthFlag)
    guard count >= longFormThreshold else { return Data([CK_BYTE(count)]) }
    var bigEndian: [CK_BYTE] = []
    var remaining = count
    while remaining > 0 {
      bigEndian.insert(CK_BYTE(remaining % octetBase), at: 0)
      remaining /= octetBase
    }
    return Data([Asn1LongFormLengthFlag | CK_BYTE(bigEndian.count)]) + bigEndian
  }

  /// Reads one byte, or nil at the end of input.
  private static func readByte(_ bytes: Data, _ index: inout Int) -> CK_BYTE? {
    guard index < bytes.count else { return nil }
    defer { index += 1 }
    return bytes[index]
  }

  /// Reads DER length octets, short or long form.
  private static func readLength(_ bytes: Data, _ index: inout Int) -> Int? {
    guard let first = readByte(bytes, &index) else { return nil }
    guard first & Asn1LongFormLengthFlag != 0 else { return Int(first) }
    let octetCount = Int(first & ~Asn1LongFormLengthFlag)
    guard octetCount > 0, octetCount <= maximumLengthOctets else { return nil }
    var length = 0
    for _ in 0..<octetCount {
      guard let octet = readByte(bytes, &index) else { return nil }
      length = length * octetBase + Int(octet)
    }
    return length
  }

  /// Reads a DER INTEGER and returns its content with leading zero
  /// octets stripped.
  private static func readInteger(_ bytes: Data, _ index: inout Int) -> Data? {
    guard readByte(bytes, &index) == Asn1IntegerTag,
      let length = readLength(bytes, &index),
      length > 0,
      index + length <= bytes.count
    else { return nil }
    var content = bytes[index..<(index + length)]
    index += length
    while content.count > 1, content.first == 0 {
      content = content.dropFirst()
    }
    return Data(content)
  }

  /// Left-pads an integer to the field width; nil when it is too wide.
  private static func padded(_ value: Data, to width: Int) -> Data? {
    guard value.count <= width else { return nil }
    return Data(repeating: 0, count: width - value.count) + value
  }
}
