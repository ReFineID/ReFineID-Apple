import Foundation

/// Extracts the full hardware serial from EF.TokenInfo content.
///
/// PKCS#15 TokenInfo is `SEQUENCE { version INTEGER, serialNumber OCTET
/// STRING, ... }`; the serial is the hex rendering of the octet string,
/// matching the reference implementation. Everything after the serial
/// is deliberately ignored - the minimal driver needs nothing else from
/// this file.
public enum TokenInfoFile {
  private static let hexDigits = Array("0123456789ABCDEF")

  private static let highNibbleShift = 4

  private static let hexDigitsPerByte = 2

  private static let minimumFieldCount = 2

  /// Parses the serial, or nil when the outer SEQUENCE, the leading
  /// INTEGER, or the serial octet string is missing or malformed.
  public static func serial(fromContent content: Data) -> TokenSerial? {
    guard
      let outer = try? DerTlvRecord.sequence(in: content),
      let sequence = outer.first,
      sequence.tag == Iso7816Values.derSequenceTag,
      let fields = try? DerTlvRecord.sequence(in: sequence.value),
      fields.count >= Self.minimumFieldCount,
      fields[0].tag == Iso7816Values.derIntegerTag,
      fields[1].tag == Iso7816Values.derOctetStringTag,
      !fields[1].value.isEmpty
    else {
      return nil
    }
    return TokenSerial(value: hexEncode(fields[1].value))
  }

  private static func hexEncode(_ data: Data) -> String {
    var rendered = ""
    rendered.reserveCapacity(data.count * Self.hexDigitsPerByte)
    for byte in data {
      rendered.append(Self.hexDigits[Int(byte) >> Self.highNibbleShift])
      rendered.append(Self.hexDigits[Int(byte) & Int(Iso7816Values.lowNibbleMask)])
    }
    return rendered
  }
}
