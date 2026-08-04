import Foundation

/// The parts of a PDF's cross-reference chain an incremental update
/// needs (ISO 32000-1 §7.5).
///
/// Everything here counts bytes, never characters. A cross-reference
/// table addresses byte offsets, and a PDF is binary with ASCII
/// structure in it: decoding the file to a string first would be wrong
/// on any document with CRLF line endings, where `\r\n` is one Swift
/// Character but two bytes - every offset after the first line ending
/// would then be short by the number of line endings before it.
internal struct PdfDocumentIndex {
  /// Maximum /Prev hops followed before the chain is called broken.
  private static let maximumChainDepth = 64

  /// Object number to byte offset, newest section winning.
  internal let offsets: [Int: Int]

  /// The newest trailer dictionary, as written.
  internal let trailer: String

  /// The offset the file's last `startxref` names.
  internal let previousStartXref: Int

  /// An integer value of a trailer key, when present.
  internal static func integer(named key: String, in dictionary: String) -> Int? {
    guard let range = dictionary.range(of: key) else { return nil }
    let rest = dictionary[range.upperBound...].drop(while: \.isWhitespace)
    return Int(rest.prefix(while: \.isNumber))
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

  /// Parses the chain from the end of the file.
  internal static func parse(_ document: Data) throws -> Self {
    let bytes = PdfBytes(document)
    guard bytes.starts(with: PdfValues.filePrefix) else {
      throw PdfSigningError.notAPdf
    }
    guard let startXref = Self.startXref(in: bytes) else {
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
      let section = try Self.section(in: bytes, at: current)
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

  /// The byte offset the last `startxref` names.
  private static func startXref(in bytes: PdfBytes) -> Int? {
    guard let found = bytes.lastRange(of: PdfValues.startXrefKeyword) else {
      return nil
    }
    return bytes.decimal(at: bytes.skippingWhitespace(from: found.upperBound))
  }

  /// One cross-reference section: its entries and its trailer.
  private static func section(
    in bytes: PdfBytes,
    at offset: Int
  ) throws -> (offsets: [Int: Int], trailer: String) {
    guard offset < bytes.count else {
      throw PdfSigningError.structureUnreadable
    }
    let start = bytes.skippingWhitespace(from: offset)
    guard bytes.hasKeyword(PdfValues.xrefKeyword, at: start) else {
      throw Self.unsupportedShape(in: bytes, at: start)
    }
    guard
      let trailerRange = bytes.firstRange(
        of: PdfValues.trailerKeyword, from: start
      )
    else {
      throw PdfSigningError.structureUnreadable
    }
    let entriesStart = start + PdfValues.xrefKeyword.utf8.count
    let entries = Self.entries(
      in: bytes.text(in: entriesStart..<trailerRange.lowerBound)
    )
    let dictionary = Self.dictionary(in: bytes, from: trailerRange.upperBound)
    return (entries, dictionary)
  }

  /// Which refusal a non-table section earns: a cross-reference stream
  /// is a shape this writer does not extend, anything else is broken.
  private static func unsupportedShape(
    in bytes: PdfBytes,
    at start: Int
  ) -> PdfSigningError {
    let windowEnd = min(start + PdfValues.streamProbeWindow, bytes.count)
    let window = bytes.text(in: start..<windowEnd)
    return window.contains(PdfValues.xrefStreamMarker)
      ? .crossReferenceStreamUnsupported
      : .structureUnreadable
  }

  /// The in-use entries of one cross-reference section.
  ///
  /// Subsections are `first count` followed by that many
  /// `offset generation flag` triples (ISO 32000-1 §7.5.4).
  private static func entries(in text: String) -> [Int: Int] {
    var found: [Int: Int] = [:]
    let tokens = text.split(whereSeparator: \.isWhitespace)
    var index = 0
    while index + PdfValues.subsectionHeaderTokens <= tokens.count,
      let first = Int(tokens[index]),
      let count = Int(tokens[index + 1])
    {
      index += PdfValues.subsectionHeaderTokens
      for entry in 0..<count
      where index + PdfValues.entryTokens <= tokens.count {
        if tokens[index + PdfValues.entryFlagIndex] == PdfValues.inUseFlag,
          let position = Int(tokens[index])
        {
          found[first + entry] = position
        }
        index += PdfValues.entryTokens
      }
    }
    return found
  }

  /// The balanced `<< >>` dictionary starting at or after `offset`.
  private static func dictionary(in bytes: PdfBytes, from offset: Int) -> String {
    guard let start = bytes.firstRange(of: "<<", from: offset) else {
      return ""
    }
    var depth = 0
    var cursor = start.lowerBound
    while cursor < bytes.count {
      if bytes.hasKeyword("<<", at: cursor) {
        depth += 1
        cursor += PdfValues.dictionaryMarkerLength
        continue
      }
      if bytes.hasKeyword(">>", at: cursor) {
        depth -= 1
        cursor += PdfValues.dictionaryMarkerLength
        if depth == 0 {
          return bytes.text(in: start.lowerBound..<cursor)
        }
        continue
      }
      cursor += 1
    }
    return ""
  }

  /// One object's body: the bytes between `obj` and `endobj`.
  internal func body(of number: Int, in document: Data) -> String? {
    guard let offset = offsets[number], offset < document.count else {
      return nil
    }
    let bytes = PdfBytes(document)
    guard
      let objRange = bytes.firstRange(of: "obj", from: offset),
      let endRange = bytes.firstRange(of: "endobj", from: objRange.upperBound)
    else {
      return nil
    }
    return bytes.text(in: objRange.upperBound..<endRange.lowerBound)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
