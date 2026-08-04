import Foundation

/// Laying the signature's mark over the document's last page
/// (ISO 32000-1 §7.8.2 content streams, §12.5.6.19 widgets).
///
/// The page keeps its own content stream untouched: PDF lets a page
/// name several, so the mark is a second stream drawn after the
/// first. That matters beyond tidiness - pages often share one
/// stream, and editing it would stamp every page that shares it.
extension PdfIncrementalSigner {
  /// The object numbers this revision writes.
  ///
  /// Allocated in one run from the trailer's size, so a reader meets
  /// them in the order they were written.
  internal struct PageNumbers {
    /// The signature's widget.
    internal let field: Int

    /// The stream drawing the mark.
    internal let content: Int

    /// Numbers, counting from the first free one: the signature takes
    /// it, then the widget and the mark's stream.
    internal init(firstFree: Int) {
      var next = firstFree
      next += 1
      self.field = next
      next += 1
      self.content = next
    }
  }

  /// Writes what this revision adds besides the signature, answering
  /// the highest object number used.
  internal static func appendRevisionBody(
    into out: inout Data,
    offsets: inout [Int: Int],
    source: RevisionSource,
    numbers: PageNumbers,
    stamp: StampMark?
  ) throws -> Int {
    guard let stamp else {
      try Self.appendReissuedObjects(
        into: &out,
        offsets: &offsets,
        source: source,
        rootNumber: source.rootNumber,
        fieldNumber: numbers.field
      )
      return numbers.field
    }
    try Self.appendStampOverlay(
      into: &out,
      offsets: &offsets,
      source: source,
      numbers: numbers,
      stamp: stamp
    )
    try Self.appendFormReissue(
      into: &out,
      offsets: &offsets,
      source: source,
      rootNumber: source.rootNumber,
      fieldNumber: numbers.field
    )
    return numbers.content
  }

  /// Writes the mark's stream and the reissued last page.
  internal static func appendStampOverlay(
    into out: inout Data,
    offsets: inout [Int: Int],
    source: RevisionSource,
    numbers: PageNumbers,
    stamp: StampMark
  ) throws {
    let index = source.index
    let document = source.document
    guard
      let catalog = index.body(of: source.rootNumber, in: document),
      let pageNumber = try? Self.lastPage(
        index: index, document: document, catalog: catalog
      ),
      let page = index.body(of: pageNumber, in: document)
    else {
      throw PdfSigningError.structureUnreadable
    }

    offsets[numbers.content] = out.count
    out.append(
      Self.markStream(numbers.content, stamp: stamp, page: page)
    )

    let reissued = Self.pageWithMark(
      page, content: numbers.content, field: numbers.field
    )
    offsets[pageNumber] = out.count
    out.append(Data("\(pageNumber) 0 obj\n\(reissued)\nendobj\n".utf8))
  }

  /// The mark's own content stream, placed in the page's margin.
  ///
  /// Encoded as Latin-1: the page draws with the standard fonts under
  /// WinAnsi, where an accented letter is one byte. It opens by
  /// resetting the graphics state, because a page whose own stream
  /// ends mid-clip would otherwise swallow the mark.
  private static func markStream(
    _ number: Int,
    stamp: StampMark,
    page: String
  ) -> Data {
    let box = Self.mediaBox(of: page)
    let placedX = box.width - stamp.radius - PdfValues.stampMargin
    let placedY = stamp.radius + PdfValues.stampMargin
    let text =
      "q 1 0 0 1 \(placedX) \(placedY) cm\n" + stamp.operators + "Q\n"
    let body =
      text.data(using: .windowsCP1252, allowLossyConversion: true)
      ?? Data(text.utf8)
    var object = Data("\(number) 0 obj\n<< /Length \(body.count) >>\nstream\n".utf8)
    object.append(body)
    object.append(Data("\nendstream\nendobj\n\n".utf8))
    return object
  }

  /// The page reissued to draw the mark, hold the widget, and know
  /// the fonts the mark uses.
  private static func pageWithMark(
    _ page: String,
    content: Int,
    field: Int
  ) -> String {
    var body = Self.namingSecondContentStream(page, content: content)
    body =
      body.contains("/Annots")
      ? Self.appendingToNamedArray(body, key: "/Annots", entry: field)
      : Self.insertingIntoDictionary(body, entry: "/Annots [\(field) 0 R]")
    return body
  }

  /// The page's `/Contents` turned into an array naming both streams.
  private static func namingSecondContentStream(
    _ page: String,
    content: Int
  ) -> String {
    guard let range = page.range(of: "/Contents") else { return page }
    let rest = page[range.upperBound...].drop(while: \.isWhitespace)
    if rest.first == "[" {
      return Self.appendingToNamedArray(page, key: "/Contents", entry: content)
    }
    let reference = rest.prefix { character in
      character.isNumber || character == " " || character == "R"
    }
    let existing = reference.trimmingCharacters(in: .whitespaces)
    return page.replacingOccurrences(
      of: "/Contents \(existing)",
      with: "/Contents [\(existing) \(content) 0 R]"
    )
  }

  /// The page's box, or A4 when it does not state one.
  private static func mediaBox(of page: String) -> (width: Double, height: Double) {
    guard
      let range = page.range(of: "/MediaBox"),
      let open = page[range.upperBound...].firstIndex(of: "["),
      let close = page[open...].firstIndex(of: "]")
    else {
      return (PdfValues.a4Width, PdfValues.a4Height)
    }
    let numbers = page[page.index(after: open)..<close]
      .split(whereSeparator: \.isWhitespace)
      .compactMap { part in Double(part) }
    guard numbers.count == PdfValues.boxCorners else {
      return (PdfValues.a4Width, PdfValues.a4Height)
    }
    // A media box reads lower-left then upper-right.
    let lowerLeftX = numbers[PdfValues.boxLowerLeftX]
    let lowerLeftY = numbers[PdfValues.boxLowerLeftY]
    let upperRightX = numbers[PdfValues.boxUpperRightX]
    let upperRightY = numbers[PdfValues.boxUpperRightY]
    return (upperRightX - lowerLeftX, upperRightY - lowerLeftY)
  }

  /// The last page of the document: the deepest tree's last kid.
  private static func lastPage(
    index: PdfDocumentIndex,
    document: Data,
    catalog: String
  ) throws -> Int {
    guard
      var current = PdfDocumentIndex.reference(named: "/Pages", in: catalog)
    else {
      throw PdfSigningError.structureUnreadable
    }
    for _ in 0..<PdfValues.pageTreeDepthLimit {
      guard let body = index.body(of: current, in: document) else {
        throw PdfSigningError.structureUnreadable
      }
      guard let kids = body.range(of: "/Kids") else { return current }
      let rest = body[kids.upperBound...]
      guard
        let open = rest.firstIndex(of: "["),
        let close = rest[open...].firstIndex(of: "]")
      else {
        throw PdfSigningError.structureUnreadable
      }
      let references = rest[rest.index(after: open)..<close]
        .split(separator: "R")
        .compactMap { part in
          Int(part.split(whereSeparator: \.isWhitespace).first ?? "")
        }
      guard let last = references.last else {
        throw PdfSigningError.structureUnreadable
      }
      current = last
    }
    throw PdfSigningError.structureUnreadable
  }

  /// A PDF date string, always UTC.
  internal static func pdfDate(_ instant: Date) -> String {
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
}
