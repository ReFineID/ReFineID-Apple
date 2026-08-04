/// The dedicated home for PDF syntax constants used by signing.
///
/// Sources: ISO 32000-1 (PDF 1.7) for file structure and the
/// signature dictionary, ETSI EN 319 142-1 for the PAdES entries.
internal enum PdfValues {
  /// Every PDF begins with this.
  internal static let filePrefix = "%PDF-"

  /// The keyword whose last occurrence names the newest cross-
  /// reference table (ISO 32000-1 §7.5.5).
  internal static let startXrefKeyword = "startxref"

  /// The cross-reference table keyword.
  internal static let xrefKeyword = "xref"

  /// The trailer keyword.
  internal static let trailerKeyword = "trailer"

  /// The end-of-file marker.
  internal static let endOfFileMarker = "%%EOF"

  /// The marker of a cross-reference stream, which this writer does
  /// not modify.
  internal static let xrefStreamMarker = "/XRef"

  /// How far past a failed `xref` keyword to look for the stream
  /// marker, to tell one unsupported shape from a broken file.
  internal static let streamProbeWindow: Int = 512

  /// Characters in `<<` and `>>`.
  internal static let dictionaryMarkerLength: Int = 2

  /// The encryption dictionary key; an encrypted document is refused.
  internal static let encryptKey = "/Encrypt"

  /// Bytes of the hole reserved for the signature's CMS (ISO 32000-1
  /// §12.8.1: /Contents must be a fixed-length hex string).
  ///
  /// 48 KiB. A qualified signature with signature timestamps from
  /// several authorities was measured needing about 23 KiB, and the
  /// hole cannot be resized after the byte ranges are fixed, so this
  /// is deliberately generous: an overflow wastes a card signature,
  /// spare zero padding costs only file size.
  internal static let signatureCapacity: Int = 49_152

  /// Bytes reserved for a document timestamp's token, which carries
  /// one authority's answer and nothing else.
  internal static let timestampCapacity: Int = 16_384

  /// Digits reserved for each /ByteRange value; a fixed width is what
  /// lets the array be patched without moving anything.
  internal static let byteRangeDigits: Int = 10

  /// Tokens introducing one cross-reference subsection: its first
  /// object number and its entry count.
  internal static let subsectionHeaderTokens: Int = 2

  /// Tokens in one cross-reference entry: offset, generation, and the
  /// in-use or free flag.
  internal static let entryTokens: Int = 3

  /// Position of the in-use flag within an entry's tokens.
  internal static let entryFlagIndex: Int = 2

  /// The flag marking an in-use entry.
  internal static let inUseFlag = "n"

  /// Values in a /ByteRange array: two offset-length pairs, one for
  /// the span before the hole and one for the span after it.
  internal static let byteRangeFieldCount: Int = 4

  /// Maximum page-tree descents before the tree is called broken.
  internal static let pageTreeDepthLimit: Int = 32

  /// Uppercase hex digits: what /Contents is written in.
  internal static let hexDigits = "0123456789ABCDEF"

  /// Hex characters per byte: the hole holds two per reserved byte.
  internal static let hexCharactersPerByte: Int = 2

  /// Bits a hex digit carries, splitting a byte into its two nibbles.
  internal static let hexDigitBits: Int = 4

  /// Mask selecting one hex digit's nibble.
  internal static let hexDigitMask: UInt8 = 0x0F

  /// The angle brackets around the hex string, which the byte ranges
  /// exclude along with the hex itself.
  internal static let hexDelimiterCount: Int = 2
}
