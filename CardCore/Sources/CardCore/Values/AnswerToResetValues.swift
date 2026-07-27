/// Structure of an answer to reset, as ISO 7816-3 section 8 defines it.
///
/// Named here rather than written into the parser, so the parser reads
/// as the standard's own description of the format.
internal enum AnswerToResetValues {
  /// Where `T0` sits: after `TS`, the convention byte.
  internal static let formatByteIndex: Int = 1

  /// How many historical bytes there are: the low nibble of `T0`.
  internal static let historicalCountMask: UInt8 = 0x0F

  /// Which bytes follow: the high nibble of `T0` and of each `TD`.
  internal static let interfacePresenceShift: UInt8 = 4

  /// Bits 1 to 3 of that nibble announce `TA`, `TB` and `TC`, in order.
  ///
  /// A set rather than three separately named constants, because the
  /// parser walks them as one.
  internal static let interfaceByteBits: [UInt8] = [
    // swiftlint:disable:next no_magic_numbers
    0x01, 0x02, 0x04,
  ]

  /// Bit 4 of it announces a further `TD`, and a further group after.
  internal static let protocolByteBit: UInt8 = 0x08
}
