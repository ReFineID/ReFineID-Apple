import Foundation

/// One parsed DER tag-length-value record with a single-byte tag.
///
/// The minimal reader below covers exactly what EF.TokenInfo needs:
/// sequential records, single-byte tags, short-form and bounded
/// long-form lengths, no recursion beyond the caller's own descent.
/// Malformed input yields nil, never a partial record
/// (Documentation/release-plan.md section 4.4).
internal struct DerTlvRecord: Equatable, Sendable {
  /// Thrown when the byte stream is not well-formed DER.
  internal struct Malformed: Error, Equatable {}

  /// Longest long-form length encoding accepted: two length bytes,
  /// enough for the 16 KiB aggregate bound with margin.
  private static let maximumLengthByteCount = 2

  /// The single-byte tag.
  internal let tag: UInt8

  /// The value bytes.
  internal let value: Data

  /// Parses consecutive records covering `data` exactly; throws when
  /// any record is malformed or lengths disagree with the data.
  internal static func sequence(in data: Data) throws -> [Self] {
    let bytes = Array(data)
    var records: [Self] = []
    var index = 0
    while index < bytes.count {
      let recordTag = bytes[index]
      index += 1
      guard index < bytes.count else { throw Malformed() }
      let lengthByte = bytes[index]
      index += 1
      var length = Int(lengthByte)
      if lengthByte & Iso7816Values.derLongFormMask != 0 {
        let lengthByteCount = Int(lengthByte & Iso7816Values.derLengthCountMask)
        guard
          lengthByteCount >= 1,
          lengthByteCount <= Self.maximumLengthByteCount,
          index + lengthByteCount <= bytes.count
        else {
          throw Malformed()
        }
        length = 0
        for _ in 0..<lengthByteCount {
          length = length << Iso7816Values.byteShift | Int(bytes[index])
          index += 1
        }
      }
      guard
        length <= BinaryReadAssembler.maximumTotalLength,
        index + length <= bytes.count
      else {
        throw Malformed()
      }
      records.append(
        Self(
          tag: recordTag,
          value: Data(bytes[index..<index + length])
        )
      )
      index += length
    }
    return records
  }
}
