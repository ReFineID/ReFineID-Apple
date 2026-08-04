import Foundation

/// Appending a page that carries the signature's visible mark
/// (ISO 32000-1 §7.7.3 the page tree, §12.5.6.19 widget annotations).
///
/// The page is added in the signature's own revision, so it is inside
/// what the signature covers, and the widget lives on it. That is why
/// nothing of the original document is reissued except the page tree
/// node and the interactive form: the document's own pages are left
/// exactly as they were.
extension PdfIncrementalSigner {
  /// The object numbers this revision writes.
  ///
  /// Allocated in one run from the trailer's size, so a reader of
  /// this revision meets them in the order they were written.
  internal struct PageNumbers {
    /// The appended page.
    internal let page: Int

    /// Its content stream.
    internal let content: Int

    /// The signature's widget, which sits on that page.
    internal let field: Int

    /// Numbers, counting from the first free one: the signature
    /// takes it, then the widget, the page and its content in the
    /// order they are written.
    internal init(firstFree: Int) {
      var next = firstFree
      next += 1
      self.field = next
      next += 1
      self.page = next
      next += 1
      self.content = next
    }
  }

  /// Writes what this revision adds besides the signature itself,
  /// answering the highest object number it used.
  ///
  /// With a stamp the widget lives on the appended page, so the
  /// document's own pages are left exactly as they were and only the
  /// page tree and the interactive form are reissued. Without one the
  /// widget has to join an existing page, which is the older path.
  internal static func appendRevisionBody(
    into out: inout Data,
    offsets: inout [Int: Int],
    source: RevisionSource,
    numbers: PageNumbers,
    stamp: StampPage?
  ) throws -> Int {
    let rootNumber = source.rootNumber
    guard let stamp else {
      try Self.appendReissuedObjects(
        into: &out,
        offsets: &offsets,
        source: source,
        rootNumber: rootNumber,
        fieldNumber: numbers.field
      )
      return numbers.field
    }
    try Self.appendStampPage(
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
      rootNumber: rootNumber,
      fieldNumber: numbers.field
    )
    return numbers.content
  }

  /// Writes the page, its content, and the reissued page tree.
  internal static func appendStampPage(
    into out: inout Data,
    offsets: inout [Int: Int],
    source: RevisionSource,
    numbers: PageNumbers,
    stamp: StampPage
  ) throws {
    let rootNumber = source.rootNumber
    let index = source.index
    let document = source.document
    guard
      let catalog = index.body(of: rootNumber, in: document),
      let treeNumber = PdfDocumentIndex.reference(named: "/Pages", in: catalog),
      let tree = index.body(of: treeNumber, in: document)
    else {
      throw PdfSigningError.structureUnreadable
    }

    offsets[numbers.page] = out.count
    out.append(Data(Self.pageObject(numbers, stamp: stamp, tree: treeNumber).utf8))

    offsets[numbers.content] = out.count
    out.append(Self.contentObject(numbers.content, stamp: stamp))

    offsets[treeNumber] = out.count
    out.append(
      Data(
        "\(treeNumber) 0 obj\n\(Self.grownTree(tree, page: numbers.page))\nendobj\n"
          .utf8
      )
    )
  }

  /// The page itself: the stamp's size, its content, the fonts it
  /// draws with, and the signature's widget.
  private static func pageObject(
    _ numbers: PageNumbers,
    stamp: StampPage,
    tree: Int
  ) -> String {
    let box = "[0 0 \(Self.trimmed(stamp.width)) \(Self.trimmed(stamp.height))]"
    return """
      \(numbers.page) 0 obj
      << /Type /Page /Parent \(tree) 0 R /MediaBox \(box)
      /Contents \(numbers.content) 0 R
      /Resources << /Font \(PdfValues.stampFonts) >>
      /Annots [\(numbers.field) 0 R] >>
      endobj

      """
  }

  /// The content stream drawing the mark.
  ///
  /// Encoded as Latin-1, not UTF-8. The page draws with the standard
  /// fonts under WinAnsi encoding, where an accented letter is one
  /// byte; written as UTF-8 its two bytes are drawn as two letters,
  /// which is how "électronique" reaches the page as "Ã©lectronique".
  /// A character outside that encoding is dropped rather than
  /// mangled - a stamp missing a letter is better than one showing
  /// nonsense.
  private static func contentObject(_ number: Int, stamp: StampPage) -> Data {
    let body =
      stamp.operators.data(using: .windowsCP1252, allowLossyConversion: true)
      ?? Data(stamp.operators.utf8)
    var object = Data(
      """
      \(number) 0 obj
      << /Length \(body.count) >>
      stream

      """.utf8
    )
    object.append(body)
    object.append(Data("\nendstream\nendobj\n\n".utf8))
    return object
  }

  /// The page tree with the appended page in it.
  ///
  /// Both the kid list and the count are grown: a tree whose count
  /// disagrees with its kids is a document readers repair rather than
  /// read.
  private static func grownTree(_ tree: String, page: Int) -> String {
    var grown = Self.appendingToNamedArray(tree, key: "/Kids", entry: page)
    guard
      let range = grown.range(of: "/Count"),
      let count = PdfDocumentIndex.integer(named: "/Count", in: grown)
    else {
      return grown
    }
    let rest = grown[range.upperBound...]
      .drop(while: \.isWhitespace)
      .prefix(while: \.isNumber)
    grown.replaceSubrange(rest.startIndex..<rest.endIndex, with: "\(count + 1)")
    return grown
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

  /// Rounds a page dimension to whole points.
  private static func trimmed(_ value: Double) -> String {
    String(format: "%.0f", value)
  }
}
