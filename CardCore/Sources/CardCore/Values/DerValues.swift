/// The dedicated home for DER wire values used by document signing.
///
/// Tags are ASN.1 universal or context-specific identifier octets
/// (X.690 §8.1.2); object identifiers are kept in dotted notation and
/// encoded arithmetically, so no encoded OID byte appears anywhere.
/// No raw hex literal may appear outside this directory
/// (`.swiftlint.yml` `unexplained_hex`).
internal enum DerValues {
  /// Universal tag: SEQUENCE, constructed.
  internal static let tagSequence: UInt8 = 0x30

  /// Universal tag: SET, constructed (X.690 §8.12).
  internal static let tagSet: UInt8 = 0x31

  /// Universal tag: INTEGER.
  internal static let tagInteger: UInt8 = 0x02

  /// Universal tag: BOOLEAN.
  internal static let tagBoolean: UInt8 = 0x01

  /// Universal tag: OCTET STRING.
  internal static let tagOctetString: UInt8 = 0x04

  /// Universal tag: OBJECT IDENTIFIER.
  internal static let tagObjectIdentifier: UInt8 = 0x06

  /// BOOLEAN TRUE content octet: DER requires all bits set.
  internal static let booleanTrue: UInt8 = 0xFF

  /// Context-specific constructed tag `[0]`.
  internal static let tagContext0Constructed: UInt8 = 0xA0

  /// Context-specific constructed tag `[1]`.
  internal static let tagContext1Constructed: UInt8 = 0xA1

  /// Context-specific constructed tag `[2]`.
  internal static let tagContext2Constructed: UInt8 = 0xA2

  /// Length byte: long-form marker bit (X.690 §8.1.3.5).
  internal static let longFormMask: UInt8 = 0x80

  /// Length byte: number-of-length-bytes mask in the long form.
  internal static let lengthCountMask: UInt8 = 0x7F

  /// Longest length this reader accepts, in octets: four covers any
  /// document a signature is taken over.
  internal static let maximumLengthOctets: Int = 4

  /// Largest length encodable in the short form.
  internal static let shortFormMaximum: Int = 127

  /// Sign bit of a content octet, deciding INTEGER zero-padding.
  internal static let signBitMask: UInt8 = 0x80

  /// Arcs an OID must have before the first two can share an octet.
  internal static let oidMinimumArcs: Int = 2

  /// OID arcs consumed by that shared first octet.
  internal static let oidSharedArcs: Int = 2

  /// OID first-arc multiplier: the first two arcs share one octet as
  /// `first * 40 + second` (X.690 §8.19.4).
  internal static let oidFirstArcMultiplier: UInt = 40

  /// Base-128 continuation bit of an OID arc octet.
  internal static let oidContinuationBit: UInt8 = 0x80

  /// Value bits per OID arc octet.
  internal static let oidArcBits: UInt = 7

  /// Mask selecting one OID arc septet.
  internal static let oidArcMask: UInt = 0x7F
}
