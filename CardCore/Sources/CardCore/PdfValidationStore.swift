import Foundation

/// The document security store: the certificates, OCSP responses and
/// CRLs a validator needs to judge a signature long after its
/// certificates expire (ISO 32000-2 §12.8.4.3, ETSI EN 319 142-1).
///
/// Written as its own incremental revision after the signature is in
/// place, because it is evidence *about* that signature. Each blob is
/// a raw stream object with no filter: a validator reading these
/// wants the bytes the responder signed, not a re-encoding.
public enum PdfValidationStore {
  /// The material collected for one signature.
  public struct Material: Equatable {
    /// Certificates of the chain, the signer's own excluded - it
    /// travels in the CMS.
    public let certificates: [Data]

    /// OCSP responses, as the responders returned them.
    public let ocspResponses: [Data]

    /// CRLs, as the issuers published them.
    public let revocationLists: [Data]

    /// Whether there is nothing to write.
    public var isEmpty: Bool {
      certificates.isEmpty && ocspResponses.isEmpty && revocationLists.isEmpty
    }

    /// Groups one signature's evidence.
    public init(
      certificates: [Data],
      ocspResponses: [Data],
      revocationLists: [Data]
    ) {
      self.certificates = certificates
      self.ocspResponses = ocspResponses
      self.revocationLists = revocationLists
    }
  }

  /// Appends the store as one incremental revision.
  ///
  /// Empty material answers the input unchanged: a revision that adds
  /// nothing is a revision that should not exist.
  public static func appended(
    to document: Data,
    material: Material
  ) throws -> Data {
    guard !material.isEmpty else { return document }
    let index = try PdfDocumentIndex.parse(document)
    guard
      let rootNumber = PdfDocumentIndex.reference(named: "/Root", in: index.trailer),
      let size = PdfDocumentIndex.integer(named: "/Size", in: index.trailer),
      let catalog = index.body(of: rootNumber, in: document)
    else {
      throw PdfSigningError.structureUnreadable
    }

    var out = document
    if out.last != UInt8(ascii: "\n") {
      out.append(UInt8(ascii: "\n"))
    }
    var offsets: [Int: Int] = [:]
    var next = max(size, 1)

    let certificateNumbers = Self.appendBlobs(
      material.certificates, into: &out, offsets: &offsets, next: &next
    )
    let ocspNumbers = Self.appendBlobs(
      material.ocspResponses, into: &out, offsets: &offsets, next: &next
    )
    let crlNumbers = Self.appendBlobs(
      material.revocationLists, into: &out, offsets: &offsets, next: &next
    )

    let storeBody = Self.storeDictionary(
      certificates: certificateNumbers,
      ocspResponses: ocspNumbers,
      revocationLists: crlNumbers
    )
    let storeNumber = next
    next += 1
    offsets[storeNumber] = out.count
    out.append(Data("\(storeNumber) 0 obj\n\(storeBody)\nendobj\n".utf8))

    offsets[rootNumber] = out.count
    let updatedCatalog = Self.catalogReferencing(storeNumber, in: catalog)
    out.append(Data("\(rootNumber) 0 obj\n\(updatedCatalog)\nendobj\n".utf8))

    let xrefOffset = out.count
    out.append(
      Data(
        PdfIncrementalSigner.crossReferenceSection(
          offsets: offsets,
          size: next,
          rootNumber: rootNumber,
          xrefOffset: xrefOffset,
          trailer: (index.trailer, index.previousStartXref)
        ).utf8
      )
    )
    return out
  }

  /// Appends one stream object per blob, answering their numbers.
  private static func appendBlobs(
    _ blobs: [Data],
    into out: inout Data,
    offsets: inout [Int: Int],
    next: inout Int
  ) -> [Int] {
    var numbers: [Int] = []
    for blob in blobs {
      let number = next
      next += 1
      offsets[number] = out.count
      out.append(Data("\(number) 0 obj\n<< /Length \(blob.count) >>\nstream\n".utf8))
      out.append(blob)
      out.append(Data("\nendstream\nendobj\n".utf8))
      numbers.append(number)
    }
    return numbers
  }

  /// The store dictionary; empty categories are omitted entirely.
  private static func storeDictionary(
    certificates: [Int],
    ocspResponses: [Int],
    revocationLists: [Int]
  ) -> String {
    var entries: [String] = []
    for (key, numbers) in [
      ("/Certs", certificates),
      ("/OCSPs", ocspResponses),
      ("/CRLs", revocationLists),
    ] where !numbers.isEmpty {
      let references = numbers.map { number in "\(number) 0 R" }
      entries.append("\(key) [\(references.joined(separator: " "))]")
    }
    return "<< \(entries.joined(separator: " ")) >>"
  }

  /// The catalog with its store reference added or replaced.
  private static func catalogReferencing(
    _ storeNumber: Int,
    in catalog: String
  ) -> String {
    guard let range = catalog.range(of: "/DSS") else {
      guard let close = catalog.range(of: ">>", options: .backwards) else {
        return catalog
      }
      return String(catalog[catalog.startIndex..<close.lowerBound])
        + "\n/DSS \(storeNumber) 0 R\n"
        + String(catalog[close.lowerBound...])
    }
    // An existing store is superseded rather than merged: this
    // revision's material is collected fresh for this signature, and
    // a validator reads the newest catalog.
    let rest = catalog[range.upperBound...]
    let afterValue =
      rest.firstIndex { character in
        character == "/" || character == ">"
      } ?? rest.endIndex
    return String(catalog[catalog.startIndex..<range.lowerBound])
      + "/DSS \(storeNumber) 0 R "
      + String(rest[afterValue...])
  }
}
