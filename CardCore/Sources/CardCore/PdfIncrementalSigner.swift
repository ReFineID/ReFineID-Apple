import Foundation

/// Appends one signature or document-timestamp revision to a PDF
/// (ISO 32000-1 §7.5.6 incremental updates, §12.8 signatures; ETSI
/// EN 319 142-1 for the PAdES entries).
///
/// The original bytes are never touched: a revision is appended, and
/// what it adds is a signature dictionary with a reserved hole, an
/// invisible widget carrying it, the page and form objects reissued
/// to reference that widget, and a cross-reference section pointing
/// back at the previous one. That is what makes the result a
/// legitimate later revision of the same document rather than a new
/// document that resembles it.
public enum PdfIncrementalSigner {
  /// What a signature revision claims in its dictionary.
  public struct SignatureClaim {
    /// The claimed signing time, written to `/M`.
    public let signedAt: Date

    /// The stated reason, when the signer gave one.
    public let reason: String?

    /// The stated place, when the signer gave one.
    public let location: String?

    /// Composes a claim.
    public init(signedAt: Date, reason: String?, location: String?) {
      self.signedAt = signedAt
      self.reason = reason
      self.location = location
    }
  }

  /// Which kind of revision to prepare.
  public enum Revision {
    /// A document timestamp: no `/M`, no `/Reason`, no `/Name` -
    /// EN 319 142-1 §5.4.3 forbids them, the token is the time.
    case documentTimestamp

    /// A qualified signature: CAdES-detached, carrying its claimed
    /// signing time in `/M` (the CMS must not carry one).
    case signature(SignatureClaim)

    /// What a signature revision claims, or nil for a timestamp.
    internal var signatureClaim: SignatureClaim? {
      switch self {
      case .documentTimestamp:
        nil
      case .signature(let claim):
        claim
      }
    }
  }

  /// The literal that opens the byte-range array.
  private static let byteRangeArrayPrefix = "/ByteRange ["

  /// The literal that opens the hex hole.
  private static let contentsPrefix = "/Contents "

  /// The reserved, fixed-width byte-range array.
  private static var byteRangePlaceholder: String {
    let field = " " + String(repeating: "0", count: PdfValues.byteRangeDigits)
    let fields = String(
      repeating: field, count: PdfValues.byteRangeFieldCount
    )
    return byteRangeArrayPrefix + fields + " ]\n"
  }

  /// Prepares the revision and patches its byte ranges.
  public static func prepare(
    _ document: Data,
    revision: Revision
  ) throws -> PdfSignaturePlaceholder {
    let index = try PdfDocumentIndex.parse(document)
    guard
      let rootNumber = PdfDocumentIndex.reference(named: "/Root", in: index.trailer),
      let size = PdfDocumentIndex.integer(named: "/Size", in: index.trailer)
    else {
      throw PdfSigningError.structureUnreadable
    }
    let signatureNumber = max(size, 1)
    let fieldNumber = signatureNumber + 1
    let capacity = Self.capacity(for: revision)

    var out = document
    if out.last != UInt8(ascii: "\n") {
      out.append(UInt8(ascii: "\n"))
    }
    var offsets: [Int: Int] = [:]
    let holes = Self.appendSignatureObject(
      into: &out,
      offsets: &offsets,
      revision: revision,
      number: signatureNumber,
      capacity: capacity
    )
    offsets[fieldNumber] = out.count
    out.append(
      Data(
        Self.widget(
          revision, field: fieldNumber, signature: signatureNumber
        ).utf8
      )
    )
    try Self.appendReissuedObjects(
      into: &out,
      offsets: &offsets,
      source: RevisionSource(document: document, index: index),
      rootNumber: rootNumber,
      fieldNumber: fieldNumber
    )
    Self.closeRevision(
      into: &out,
      offsets: offsets,
      size: fieldNumber + 1,
      rootNumber: rootNumber,
      index: index
    )
    return Self.patched(
      document: out, holes: holes, capacity: capacity
    )
  }

  /// Appends the cross-reference section and trailer.
  private static func closeRevision(
    into out: inout Data,
    offsets: [Int: Int],
    size: Int,
    rootNumber: Int,
    index: PdfDocumentIndex
  ) {
    let xrefOffset = out.count
    out.append(
      Data(
        Self.crossReferenceSection(
          offsets: offsets,
          size: size,
          rootNumber: rootNumber,
          xrefOffset: xrefOffset,
          trailer: (index.trailer, index.previousStartXref)
        ).utf8
      )
    )
  }

  /// Patches the byte ranges now that the file's length is final.
  private static func patched(
    document: Data,
    holes: (byteRangeAt: Int, contentsOpen: Int),
    capacity: Int
  ) -> PdfSignaturePlaceholder {
    var out = document
    let hexLength = capacity * PdfValues.hexCharactersPerByte
    let secondSpanStart = holes.contentsOpen + 1 + hexLength + 1
    Self.patchByteRange(
      into: &out,
      at: holes.byteRangeAt,
      values: [
        0, holes.contentsOpen, secondSpanStart, out.count - secondSpanStart,
      ]
    )
    return PdfSignaturePlaceholder(
      document: out,
      contentsOpen: holes.contentsOpen,
      secondSpanStart: secondSpanStart,
      capacity: capacity
    )
  }

  /// Appends the signature dictionary, answering where its two
  /// placeholders landed.
  private static func appendSignatureObject(
    into out: inout Data,
    offsets: inout [Int: Int],
    revision: Revision,
    number: Int,
    capacity: Int
  ) -> (byteRangeAt: Int, contentsOpen: Int) {
    offsets[number] = out.count
    out.append(Data(Self.signatureHeader(revision, number: number).utf8))
    let byteRangeAt = out.count + Self.byteRangeArrayPrefix.count
    out.append(Data(Self.byteRangePlaceholder.utf8))
    let contentsOpen = out.count + Self.contentsPrefix.count
    out.append(Data(Self.contentsPlaceholder(capacity: capacity).utf8))
    out.append(Data(">>\nendobj\n".utf8))
    return (byteRangeAt, contentsOpen)
  }

  /// The reserved hex hole, all zero padding until filled.
  private static func contentsPlaceholder(capacity: Int) -> String {
    let hexLength = capacity * PdfValues.hexCharactersPerByte
    return contentsPrefix + "<" + String(repeating: "0", count: hexLength)
      + ">\n"
  }

  /// Bytes reserved for this revision's structure.
  private static func capacity(for revision: Revision) -> Int {
    switch revision {
    case .signature:
      PdfValues.signatureCapacity
    case .documentTimestamp:
      PdfValues.timestampCapacity
    }
  }

  /// The signature dictionary up to its byte-range array.
  private static func signatureHeader(_ revision: Revision, number: Int) -> String {
    guard let claim = revision.signatureClaim else {
      return "\(number) 0 obj\n<< /Type /DocTimeStamp /Filter /Adobe.PPKLite"
        + " /SubFilter /ETSI.RFC3161\n"
    }
    var text = "\(number) 0 obj\n<< /Type /Sig /Filter /Adobe.PPKLite"
    text += " /SubFilter /ETSI.CAdES.detached\n"
    if let reason = claim.reason {
      text += "/Reason (\(Self.escaped(reason)))\n"
    }
    if let location = claim.location {
      text += "/Location (\(Self.escaped(location)))\n"
    }
    text += "/M (\(Self.pdfDate(claim.signedAt)))\n"
    return text
  }

  /// The invisible signature widget.
  ///
  /// Its name is built from the signature's object number, which is
  /// unique in the document by construction. A fixed name would not
  /// be: two fields with the same fully qualified name are the same
  /// field (ISO 32000-1 §12.7.3.2), so signing a signed document
  /// again would give one name two signature dictionaries. A
  /// validator resolving that name reaches the first, compares it
  /// against the second, and reports the signature dictionary as
  /// inconsistent between the signed and the final revision - which
  /// is what a second signature was doing until this was fixed.
  private static func widget(
    _ revision: Revision,
    field: Int,
    signature: Int
  ) -> String {
    let name: String
    switch revision {
    case .signature:
      name = "Signature\(signature)"
    case .documentTimestamp:
      name = "Timestamp\(signature)"
    }
    return "\(field) 0 obj\n<< /Type /Annot /Subtype /Widget /FT /Sig"
      + " /T (\(name)) /V \(signature) 0 R /Rect [0 0 0 0] /F 132 >>\nendobj\n"
  }

  /// A PDF date string, always UTC.
  private static func pdfDate(_ instant: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(identifier: "UTC") else {
      return ""
    }
    calendar.timeZone = utc
    let parts = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: instant
    )
    return String(
      format: "D:%04d%02d%02d%02d%02d%02d+00'00'",
      parts.year ?? 0,
      parts.month ?? 0,
      parts.day ?? 0,
      parts.hour ?? 0,
      parts.minute ?? 0,
      parts.second ?? 0
    )
  }

  /// A literal string's escapes: backslash and both parentheses.
  private static func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "(", with: "\\(")
      .replacingOccurrences(of: ")", with: "\\)")
  }

  /// Writes the four values into the reserved array, right-aligned
  /// in their fixed-width fields so nothing moves.
  private static func patchByteRange(
    into document: inout Data,
    at offset: Int,
    values: [Int]
  ) {
    let stride = PdfValues.byteRangeDigits + 1
    for (index, value) in values.enumerated() {
      let text = String(value)
      let padded =
        String(
          repeating: " ", count: PdfValues.byteRangeDigits - text.count
        ) + text
      let start = offset + index * stride + 1
      for (position, byte) in padded.utf8.enumerated() {
        document[start + position] = byte
      }
    }
  }
}
