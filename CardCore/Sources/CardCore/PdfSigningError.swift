/// Why a PDF could not be prepared or signed.
public enum PdfSigningError: Error, Equatable {
  /// The newest cross-reference section is a stream, which this
  /// writer does not rewrite.
  case crossReferenceStreamUnsupported

  /// The document is encrypted; this writer will not touch it.
  case encrypted

  /// The bytes do not begin as a PDF.
  case notAPdf

  /// The assembled structure outgrew its reserved hole; the hole
  /// cannot be resized after the byte ranges are fixed.
  case signatureTooLarge(needed: Int, reserved: Int)

  /// The catalog, page tree or trailer could not be followed.
  case structureUnreadable
}
