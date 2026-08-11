//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
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
    try Self.prepare(document, revision: revision, appending: nil)
  }

  /// The same, showing the signature's visible mark.
  ///
  /// The mark is the signature widget's own appearance, laid over the
  /// last page's margin. An appearance is not page content: it adds
  /// nothing to what an earlier signature covered, so a second signer
  /// can leave a mark without breaking the first one.
  public static func prepare(
    _ document: Data,
    revision: Revision,
    appending stamp: StampMark?
  ) throws -> PdfSignaturePlaceholder {
    let index = try PdfDocumentIndex.parse(document)
    guard
      let rootNumber = PdfDocumentIndex.reference(named: "/Root", in: index.trailer),
      let size = PdfDocumentIndex.integer(named: "/Size", in: index.trailer)
    else {
      throw PdfSigningError.structureUnreadable
    }
    let signatureNumber = max(size, 1)
    let numbers = PageNumbers(firstFree: signatureNumber)
    let capacity = Self.capacity(for: revision)

    var out = Self.newlineTerminated(document)
    var offsets: [Int: Int] = [:]
    let holes = Self.appendSignatureObject(
      into: &out,
      offsets: &offsets,
      revision: revision,
      number: signatureNumber,
      capacity: capacity
    )
    let source = RevisionSource(
      document: document, index: index, rootNumber: rootNumber
    )
    offsets[numbers.field] = out.count
    out.append(
      try Self.fieldObject(
        revision: revision,
        source: source,
        numbers: numbers,
        signature: signatureNumber,
        stamp: stamp
      )
    )
    let highest = try Self.appendRevisionBody(
      into: &out,
      offsets: &offsets,
      source: source,
      numbers: numbers,
      stamp: stamp
    )
    try Self.closeRevision(
      into: &out,
      offsets: offsets,
      size: highest + 1,
      rootNumber: rootNumber,
      index: index
    )
    return Self.patched(
      document: out, holes: holes, capacity: capacity
    )
  }

  /// The document, ending in a newline so what follows starts on a
  /// line of its own.
  private static func newlineTerminated(_ document: Data) -> Data {
    guard document.last != UInt8(ascii: "\n") else { return document }
    var out = document
    out.append(UInt8(ascii: "\n"))
    return out
  }

  /// The signature field, showing its mark when there is one.
  ///
  /// The mark is the field's own appearance, so the field has to know
  /// where it sits before it is written.
  private static func fieldObject(
    revision: Revision,
    source: RevisionSource,
    numbers: PageNumbers,
    signature: Int,
    stamp: StampMark?
  ) throws -> Data {
    let placement = try stamp.map { mark in
      try Self.stampPlacement(source: source, stamp: mark)
    }
    return Data(
      Self.widget(
        revision,
        field: numbers.field,
        signature: signature,
        showing: placement.map { found in
          (rectangle: found.rectangle, appearance: numbers.appearance)
        }
      ).utf8
    )
  }

  /// Appends the cross-reference section and trailer.
  private static func closeRevision(
    into out: inout Data,
    offsets: [Int: Int],
    size: Int,
    rootNumber: Int,
    index: PdfDocumentIndex
  ) throws {
    let xrefOffset = out.count
    out.append(
      try Self.crossReferenceSection(
        offsets: offsets,
        size: size,
        rootNumber: rootNumber,
        xrefOffset: xrefOffset,
        index: index
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
    signature: Int,
    showing: (rectangle: String, appearance: Int)?
  ) -> String {
    let name: String
    switch revision {
    case .signature:
      name = "Signature\(signature)"
    case .documentTimestamp:
      name = "Timestamp\(signature)"
    }
    // A field with no appearance is invisible, which is what a
    // document timestamp and an unstamped signature want. One with an
    // appearance names the box it fills and the stream that fills it,
    // and carries the key that lets a later signing count it.
    let visible =
      showing.map { found in
        " /Rect \(found.rectangle) /AP << /N \(found.appearance) 0 R >>"
          + " \(PdfValues.stampMarker) true"
      } ?? " /Rect [0 0 0 0]"
    return "\(field) 0 obj\n<< /Type /Annot /Subtype /Widget /FT /Sig"
      + " /T (\(name)) /V \(signature) 0 R\(visible) /F 132 >>\nendobj\n"
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
