import Foundation

/// Reissuing the objects that must reference the new widget: the page
/// carrying it and the interactive form listing it (ISO 32000-1
/// §12.7.2, §12.5).
///
/// Reissuing means writing the object again, with its original number
/// and one entry added. The earlier version stays in the file - that
/// is what an incremental update is - and the new cross-reference
/// section decides which one a reader sees.
extension PdfIncrementalSigner {
  /// The document being revised and its parsed cross-reference chain.
  internal struct RevisionSource {
    /// The original bytes.
    internal let document: Data

    /// Its newest cross-reference section and trailer.
    internal let index: PdfDocumentIndex
  }

  /// Appends the reissued page and form objects.
  internal static func appendReissuedObjects(
    into out: inout Data,
    offsets: inout [Int: Int],
    source: RevisionSource,
    rootNumber: Int,
    fieldNumber: Int
  ) throws {
    let index = source.index
    let document = source.document
    guard let catalog = index.body(of: rootNumber, in: document) else {
      throw PdfSigningError.structureUnreadable
    }
    let pageNumber = try Self.firstPage(
      index: index, document: document, catalog: catalog
    )
    guard let page = index.body(of: pageNumber, in: document) else {
      throw PdfSigningError.structureUnreadable
    }

    let pageEntry = Self.pageReissue(
      source: source, page: page, pageNumber: pageNumber, field: fieldNumber
    )
    var reissued: [(number: Int, body: String)] = [pageEntry]
    reissued.append(
      Self.formReissue(
        source: source,
        catalog: catalog,
        rootNumber: rootNumber,
        field: fieldNumber
      )
    )
    for entry in reissued {
      offsets[entry.number] = out.count
      out.append(Data("\(entry.number) 0 obj\n\(entry.body)\nendobj\n".utf8))
    }
  }

  /// The page object reissued so its annotations include the widget.
  private static func pageReissue(
    source: RevisionSource,
    page: String,
    pageNumber: Int,
    field: Int
  ) -> (number: Int, body: String) {
    if let annotsNumber = PdfDocumentIndex.reference(named: "/Annots", in: page),
      let annots = source.index.body(of: annotsNumber, in: source.document)
    {
      return (annotsNumber, Self.appendingToArray(annots, entry: field))
    }
    if page.contains("/Annots") {
      return (
        pageNumber,
        Self.appendingToNamedArray(page, key: "/Annots", entry: field)
      )
    }
    return (
      pageNumber,
      Self.insertingIntoDictionary(page, entry: "/Annots [\(field) 0 R]")
    )
  }

  /// The form object reissued so its field list includes the widget.
  ///
  /// A document with no interactive form gets one, with the flags a
  /// signed form needs (ISO 32000-1 §12.7.2).
  private static func formReissue(
    source: RevisionSource,
    catalog: String,
    rootNumber: Int,
    field: Int
  ) -> (number: Int, body: String) {
    guard
      let acroNumber = PdfDocumentIndex.reference(named: "/AcroForm", in: catalog),
      let acroForm = source.index.body(of: acroNumber, in: source.document)
    else {
      if catalog.contains("/AcroForm") {
        return (
          rootNumber,
          Self.appendingToNamedArray(catalog, key: "/Fields", entry: field)
        )
      }
      return (
        rootNumber,
        Self.insertingIntoDictionary(
          catalog,
          entry: "/AcroForm << /Fields [\(field) 0 R] /SigFlags 3 >>"
        )
      )
    }
    if let fieldsNumber = PdfDocumentIndex.reference(named: "/Fields", in: acroForm),
      let fields = source.index.body(of: fieldsNumber, in: source.document)
    {
      return (fieldsNumber, Self.appendingToArray(fields, entry: field))
    }
    if acroForm.contains("/Fields") {
      return (
        acroNumber,
        Self.appendingToNamedArray(acroForm, key: "/Fields", entry: field)
      )
    }
    return (
      acroNumber,
      Self.insertingIntoDictionary(acroForm, entry: "/Fields [\(field) 0 R]")
    )
  }

  /// The cross-reference section and trailer closing the revision.
  ///
  /// One subsection per object, because the numbers a revision
  /// touches are not contiguous. `/Prev` chains to the section this
  /// revision supersedes; `/ID` and `/Info` are carried forward
  /// because a reader expects them to survive.
  internal static func crossReferenceSection(
    offsets: [Int: Int],
    size: Int,
    rootNumber: Int,
    xrefOffset: Int,
    trailer: (text: String, previousStartXref: Int)
  ) -> String {
    let previousStartXref = trailer.previousStartXref
    let trailerText = trailer.text
    var text = "xref\n"
    for number in offsets.keys.sorted() {
      guard let offset = offsets[number] else { continue }
      text += "\(number) 1\n"
      text += String(format: "%010d 00000 n \n", offset)
    }
    var carried = ""
    if let identifier = Self.bracketedValue(named: "/ID", in: trailerText) {
      carried += " /ID \(identifier)"
    }
    if let info = PdfDocumentIndex.reference(named: "/Info", in: trailerText) {
      carried += " /Info \(info) 0 R"
    }
    text += "trailer\n<< /Size \(size) /Root \(rootNumber) 0 R"
    text += " /Prev \(previousStartXref)\(carried) >>\n"
    text += "startxref\n\(xrefOffset)\n\(PdfValues.endOfFileMarker)\n"
    return text
  }

  /// The first page object: descend the tree's first kid.
  private static func firstPage(
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
      guard let kids = body.range(of: "/Kids") else {
        return current
      }
      let rest = body[kids.upperBound...]
      guard
        let open = rest.firstIndex(of: "["),
        let first = Int(
          rest[rest.index(after: open)...]
            .drop(while: { $0 == " " })
            .prefix(while: \.isNumber)
        )
      else {
        throw PdfSigningError.structureUnreadable
      }
      current = first
    }
    throw PdfSigningError.structureUnreadable
  }

  /// A bracketed array value, copied verbatim.
  private static func bracketedValue(
    named key: String,
    in dictionary: String
  ) -> String? {
    guard
      let range = dictionary.range(of: key),
      let open = dictionary[range.upperBound...].firstIndex(of: "["),
      let close = dictionary[open...].firstIndex(of: "]")
    else {
      return nil
    }
    return String(dictionary[open...close])
  }

  /// Appends a reference before an array body's closing bracket.
  private static func appendingToArray(_ body: String, entry: Int) -> String {
    guard let close = body.lastIndex(of: "]") else { return body }
    return String(body[body.startIndex..<close]) + " \(entry) 0 R"
      + String(body[close...])
  }

  /// Appends a reference inside the named key's array.
  private static func appendingToNamedArray(
    _ body: String,
    key: String,
    entry: Int
  ) -> String {
    guard
      let range = body.range(of: key),
      let close = body[range.upperBound...].firstIndex(of: "]")
    else {
      return body
    }
    return String(body[body.startIndex..<close]) + " \(entry) 0 R"
      + String(body[close...])
  }

  /// Inserts an entry before a dictionary's closing marker.
  private static func insertingIntoDictionary(
    _ body: String,
    entry: String
  ) -> String {
    guard let close = body.range(of: ">>", options: .backwards) else {
      return body
    }
    return String(body[body.startIndex..<close.lowerBound]) + "\n\(entry)\n"
      + String(body[close.lowerBound...])
  }
}
