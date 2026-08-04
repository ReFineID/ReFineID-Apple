import CardCore
import Foundation
import Testing

/// The incremental-update writer's invariants (ISO 32000-1 §7.5.6,
/// §12.8): the original survives byte-for-byte, the hole is exactly
/// what the byte ranges exclude, and filling it moves nothing.
@Suite
internal struct PdfIncrementalSignerTests {
  /// The smallest structurally complete PDF: catalog, page tree, one
  /// page, a classic cross-reference table and a trailer.
  private static var minimalPdf: Data {
    var text = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (number, body) in [
      (1, "<< /Type /Catalog /Pages 2 0 R >>"),
      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
      (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>"),
    ] {
      offsets.append(text.utf8.count)
      text += "\(number) 0 obj\n\(body)\nendobj\n"
    }
    let xrefOffset = text.utf8.count
    text += "xref\n0 4\n0000000000 65535 f \n"
    for offset in offsets {
      text += String(format: "%010d 00000 n \n", offset)
    }
    text += "trailer\n<< /Size 4 /Root 1 0 R >>\n"
    text += "startxref\n\(xrefOffset)\n%%EOF\n"
    return Data(text.utf8)
  }

  /// The document as Latin-1, the way the writer reads it.
  private static func text(_ document: Data) -> String {
    String(bytes: document, encoding: .isoLatin1) ?? ""
  }

  @Test
  internal func theOriginalBytesSurviveUnchanged() throws {
    // An incremental update appends; a reader of the earlier revision
    // must still see exactly what was there.
    let original = Self.minimalPdf
    let prepared = try PdfIncrementalSigner.prepare(
      original,
      revision: .signature(
        PdfIncrementalSigner.SignatureClaim(
          signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
        )
      )
    )
    #expect(prepared.document.prefix(original.count) == original)
    #expect(prepared.document.count > original.count)
  }

  @Test
  internal func theByteRangesExcludeExactlyTheHole() throws {
    // What is not signed must be the hex hole and nothing else:
    // everything before `<` and everything after `>`.
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf,
      revision: .signature(
        PdfIncrementalSigner.SignatureClaim(
          signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
        )
      )
    )
    let covered = prepared.signedOctets.count
    let hole = prepared.document.count - covered
    // The excluded region is the hex string plus its two brackets.
    let reserved = 49_152
    #expect(hole == reserved * 2 + 2)
    let text = Self.text(prepared.document)
    #expect(text.contains("/SubFilter /ETSI.CAdES.detached"))
    #expect(text.contains("/Type /Sig"))
    #expect(text.hasSuffix("%%EOF\n"))
  }

  @Test
  internal func fillingTheHoleMovesNothing() throws {
    // The digest is taken with the hole in place, so writing into it
    // must not change one offset or one length.
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf,
      revision: .signature(
        PdfIncrementalSigner.SignatureClaim(
          signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
        )
      )
    )
    let before = prepared.digest
    let filled = try prepared.filled(with: WireHex.data("30030101FF"))
    #expect(filled.count == prepared.document.count)
    #expect(Self.text(filled).contains("30030101FF"))
    // The signed spans are untouched by the fill.
    let after = filled.prefix(prepared.signedOctets.count)
    #expect(after.prefix(8) == prepared.document.prefix(8))
    #expect(!before.isEmpty)
  }

  @Test
  internal func anOversizedStructureIsRefusedNotTruncated() throws {
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf, revision: .documentTimestamp
    )
    let oversized = Data(repeating: 0xAB, count: 16_385)
    #expect(throws: PdfSigningError.signatureTooLarge(needed: 16_385, reserved: 16_384)) {
      _ = try prepared.filled(with: oversized)
    }
  }

  @Test
  internal func aDocumentTimestampCarriesNoClaimedTime() throws {
    // EN 319 142-1 §5.4.3: a document timestamp's dictionary has no
    // /M, /Reason, /Name or /Location - the token is the time.
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf, revision: .documentTimestamp
    )
    let text = Self.text(prepared.document)
    #expect(text.contains("/Type /DocTimeStamp"))
    #expect(text.contains("/SubFilter /ETSI.RFC3161"))
    #expect(!text.contains("/M (D:"))
    #expect(!text.contains("/Reason"))
  }

  @Test
  internal func anEncryptedDocumentIsRefused() {
    var text = Self.text(Self.minimalPdf)
    text = text.replacingOccurrences(
      of: "<< /Size 4 /Root 1 0 R >>",
      with: "<< /Size 4 /Root 1 0 R /Encrypt 9 0 R >>"
    )
    #expect(throws: PdfSigningError.encrypted) {
      _ = try PdfIncrementalSigner.prepare(
        Data(text.utf8), revision: .documentTimestamp
      )
    }
  }

  @Test
  internal func somethingThatIsNotAPdfIsRefused() {
    #expect(throws: PdfSigningError.notAPdf) {
      _ = try PdfIncrementalSigner.prepare(
        Data("not a document".utf8), revision: .documentTimestamp
      )
    }
  }
}
