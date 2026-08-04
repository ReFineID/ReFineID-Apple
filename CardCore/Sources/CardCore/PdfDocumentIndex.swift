import Foundation

/// The parts of a PDF's cross-reference chain an incremental update
/// needs (ISO 32000-1 §7.5).
///
/// Only what signing requires: where the newest table is, what the
/// trailer says, and where each generation-0 object body lives. The
/// original bytes are never rewritten - an update appends - so this
/// reads and never edits.
internal struct PdfDocumentIndex {
  /// Maximum /Prev hops followed before the chain is called broken.
  private static let maximumChainDepth = 64

  /// Object number to byte offset, newest section winning.
  internal let offsets: [Int: Int]

  /// The newest trailer dictionary, as written.
  internal let trailer: String

  /// The offset the file's last `startxref` names.
  internal let previousStartXref: Int

  /// Parses the chain from the end of the file.
  internal static func parse(_ document: Data) throws -> Self {
    let text = Self.latin1(document)
    guard text.hasPrefix(PdfValues.filePrefix) else {
      throw PdfSigningError.notAPdf
    }
    guard let startXref = Self.startXref(in: text) else {
      throw PdfSigningError.structureUnreadable
    }
    var collected: [Int: Int] = [:]
    var newestTrailer: String?
    var offset: Int? = startXref
    var visited: Set<Int> = []
    var depth = 0
    while let current = offset, depth < Self.maximumChainDepth {
      guard visited.insert(current).inserted else { break }
      depth += 1
      let section = try Self.section(in: text, at: current)
      for (number, position) in section.offsets where collected[number] == nil {
        collected[number] = position
      }
      if newestTrailer == nil {
        newestTrailer = section.trailer
      }
      offset = Self.integer(named: "/Prev", in: section.trailer)
    }
    guard let newest = newestTrailer else {
      throw PdfSigningError.structureUnreadable
    }
    guard !newest.contains(PdfValues.encryptKey) else {
      throw PdfSigningError.encrypted
    }
    return Self(
      offsets: collected, trailer: newest, previousStartXref: startXref
    )
  }

  /// An integer value of a trailer key, when present.
  internal static func integer(named key: String, in dictionary: String) -> Int? {
    guard let range = dictionary.range(of: key) else { return nil }
    let rest = dictionary[range.upperBound...].drop(while: \.isWhitespace)
    let digits = rest.prefix(while: \.isNumber)
    return Int(digits)
  }

  /// The object number of an indirect reference value, when the key
  /// holds one.
  internal static func reference(
    named key: String,
    in dictionary: String
  ) -> Int? {
    guard let range = dictionary.range(of: key) else { return nil }
    let rest = dictionary[range.upperBound...].drop(while: \.isWhitespace)
    guard rest.first?.isNumber == true else { return nil }
    return Int(rest.prefix(while: \.isNumber))
  }

  /// Bytes as Latin-1: every byte maps to one character, so a string
  /// offset is a byte offset.
  ///
  /// PDF structure is ASCII embedded in binary, and the offsets in a
  /// cross-reference table count bytes. A UTF-8 reading would collapse
  /// multi-byte sequences and move every offset after them, so the
  /// mapping has to be one byte to one character.
  internal static func latin1(_ document: Data) -> String {
    String(bytes: document, encoding: .isoLatin1) ?? ""
  }

  /// The offset the last `startxref` names.
  private static func startXref(in text: String) -> Int? {
    guard
      let range = text.range(of: PdfValues.startXrefKeyword, options: .backwards)
    else {
      return nil
    }
    let rest = text[range.upperBound...].drop(while: \.isWhitespace)
    return Int(rest.prefix(while: \.isNumber))
  }

  /// One cross-reference section: its entries and its trailer.
  private static func section(
    in text: String,
    at offset: Int
  ) throws -> (offsets: [Int: Int], trailer: String) {
    guard offset < text.count else {
      throw PdfSigningError.structureUnreadable
    }
    let start = text.index(text.startIndex, offsetBy: offset)
    let tail = text[start...].drop(while: \.isWhitespace)
    guard tail.hasPrefix(PdfValues.xrefKeyword) else {
      let window = tail.prefix(PdfValues.streamProbeWindow)
      throw window.contains(PdfValues.xrefStreamMarker)
        ? PdfSigningError.crossReferenceStreamUnsupported
        : PdfSigningError.structureUnreadable
    }
    guard let trailerRange = tail.range(of: PdfValues.trailerKeyword) else {
      throw PdfSigningError.structureUnreadable
    }
    let entriesText = tail[tail.startIndex..<trailerRange.lowerBound]
      .dropFirst(PdfValues.xrefKeyword.count)
    let parsed = Self.entries(in: entriesText)
    let trailerText = Self.dictionary(in: tail[trailerRange.upperBound...])
    return (parsed, trailerText)
  }

  /// The in-use entries of one cross-reference section.
  ///
  /// Subsections are `first count` followed by that many
  /// `offset generation flag` triples (ISO 32000-1 §7.5.4).
  private static func entries(in text: Substring) -> [Int: Int] {
    var found: [Int: Int] = [:]
    var tokens = text.split(whereSeparator: \.isWhitespace)[...]
    while tokens.count >= PdfValues.subsectionHeaderTokens,
      let first = Int(tokens[tokens.startIndex]),
      let count = Int(tokens[tokens.index(after: tokens.startIndex)])
    {
      tokens = tokens.dropFirst(PdfValues.subsectionHeaderTokens)
      for index in 0..<count where tokens.count >= PdfValues.entryTokens {
        let flagIndex = tokens.index(
          tokens.startIndex, offsetBy: PdfValues.entryFlagIndex
        )
        if tokens[flagIndex] == PdfValues.inUseFlag,
          let position = Int(tokens[tokens.startIndex])
        {
          found[first + index] = position
        }
        tokens = tokens.dropFirst(PdfValues.entryTokens)
      }
    }
    return found
  }

  /// The balanced `<< >>` dictionary at the start of a slice.
  private static func dictionary(in slice: Substring) -> String {
    guard let open = slice.range(of: "<<") else { return "" }
    var depth = 0
    var index = open.lowerBound
    while index < slice.endIndex {
      if slice[index...].hasPrefix("<<") {
        depth += 1
        index = slice.index(index, offsetBy: PdfValues.dictionaryMarkerLength)
        continue
      }
      if slice[index...].hasPrefix(">>") {
        depth -= 1
        index = slice.index(index, offsetBy: PdfValues.dictionaryMarkerLength)
        if depth == 0 {
          return String(slice[open.lowerBound..<index])
        }
        continue
      }
      index = slice.index(after: index)
    }
    return ""
  }

  /// One object's body: the bytes between `obj` and `endobj`.
  internal func body(of number: Int, in document: Data) -> String? {
    guard let offset = offsets[number], offset < document.count else {
      return nil
    }
    let text = Self.latin1(document)
    let start = text.index(text.startIndex, offsetBy: offset)
    guard
      let objRange = text.range(of: "obj", range: start..<text.endIndex),
      let endRange = text.range(
        of: "endobj", range: objRange.upperBound..<text.endIndex
      )
    else {
      return nil
    }
    return String(text[objRange.upperBound..<endRange.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
