#if os(macOS)

  import Foundation
  import Security

  extension EuTrustedListDirectory {
    /// Authenticated metadata needed before one pointer is scheduled.
    private struct PointerMetadata {
      let location: String
      let territory: String?
    }

    /// One exact national-list pointer authenticated by the LOTL.
    internal struct TrustedListPointer: Sendable {
      /// The HTTP(S) location signed into the LOTL.
      internal let location: String

      /// Exact DER certificates authorized for this one location.
      internal let signingCertificates: Set<Data>

      /// Scheme territory authenticated beside this location.
      internal let territory: String?
    }

    /// Authenticated LOTL entries retained only as historical archives.
    private static let historicalTerritories: Set<String> = ["UK"]

    /// ETSI XML trusted-list media type used by extensionless pointers.
    private static let trustedListMimeType = "application/vnd.etsi.tsl+xml"

    /// Non-XML scheme-information documents do not participate in the walk.
    private static let pdfMimeType = "application/pdf"

    /// National XML locations and their signer certificates.
    ///
    /// The caller must first verify the complete `list` through
    /// `TrustedListXmlSignature`; the relationship returned here is
    /// trustworthy only because the pointer and certificates share
    /// that authenticated XML subtree.
    internal static func trustedListPointers(
      in list: Data
    ) throws -> [TrustedListPointer] {
      let document = try XMLDocument(data: list, options: Self.xmlOptions)
      let nodes = try document.nodes(
        forXPath: "//*[local-name()='OtherTSLPointer']"
      )
      var ordered: [TrustedListPointer] = []
      var seen: [String: TrustedListPointer] = [:]
      for node in nodes {
        guard let metadata = try Self.pointerMetadata(in: node) else { continue }
        let certificates = try Self.signingCertificates(in: node)
        guard !certificates.isEmpty else { throw Failure.unusableResponse }
        if let previous = seen[metadata.location] {
          guard
            previous.signingCertificates == certificates,
            previous.territory == metadata.territory
          else {
            throw Failure.unusableResponse
          }
          continue
        }
        let pointer = TrustedListPointer(
          location: metadata.location,
          signingCertificates: certificates,
          territory: metadata.territory
        )
        seen[metadata.location] = pointer
        ordered.append(pointer)
      }
      return ordered
    }

    /// Validated URL and territory for one current XML pointer.
    private static func pointerMetadata(
      in pointer: XMLNode
    ) throws -> PointerMetadata? {
      let territory = try Self.territory(in: pointer)
      if territory.map(Self.historicalTerritories.contains) == true {
        return nil
      }
      let mimeType = try Self.mimeType(in: pointer)
      if mimeType == Self.pdfMimeType { return nil }
      let locations = try pointer.nodes(
        forXPath: "./*[local-name()='TSLLocation']"
      )
      guard
        locations.count == 1,
        let location = locations.first?.stringValue?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !location.isEmpty
      else {
        throw Failure.unusableResponse
      }
      if location == Self.listOfLists { return nil }
      guard mimeType == Self.trustedListMimeType else {
        throw Failure.unusableResponse
      }
      guard
        let url = URL(string: location),
        let scheme = url.scheme?.lowercased(),
        ["http", "https"].contains(scheme)
      else {
        throw Failure.unusableResponse
      }
      return PointerMetadata(location: location, territory: territory)
    }

    /// The one authenticated scheme territory, when supplied.
    private static func territory(in pointer: XMLNode) throws -> String? {
      let territories = try pointer.nodes(
        forXPath: "./*[local-name()='AdditionalInformation']"
          + "/*[local-name()='OtherInformation']"
          + "/*[local-name()='SchemeTerritory']"
      )
      guard territories.count <= 1 else { throw Failure.unusableResponse }
      return territories.first?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The one authenticated media type, normalized for comparison.
    private static func mimeType(in pointer: XMLNode) throws -> String? {
      let nodes = try pointer.nodes(
        forXPath: "./*[local-name()='AdditionalInformation']"
          + "/*[local-name()='OtherInformation']"
          + "/*[local-name()='MimeType']"
      )
      guard nodes.count <= 1 else { throw Failure.unusableResponse }
      return nodes.first?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    }

    /// The exact DER signer candidates inside one pointer subtree.
    private static func signingCertificates(
      in pointer: XMLNode
    ) throws -> Set<Data> {
      let nodes = try pointer.nodes(
        forXPath: "./*[local-name()='ServiceDigitalIdentities']"
          + "/*[local-name()='ServiceDigitalIdentity']"
          + "/*[local-name()='DigitalId']"
          + "/*[local-name()='X509Certificate']"
      )
      return try Set(
        nodes.map { certificate in
          guard
            let encoded = Self.base64(certificate.stringValue),
            SecCertificateCreateWithData(nil, encoded as CFData) != nil
          else {
            throw Failure.unusableResponse
          }
          return encoded
        })
    }

    /// Strict base64 after removing XML whitespace.
    private static func base64(_ encoded: String?) -> Data? {
      guard let encoded else { return nil }
      let xmlWhitespace: Set<Character> = [" ", "\t", "\n", "\r"]
      let compact = encoded.filter { character in
        !xmlWhitespace.contains(character)
      }
      guard compact.unicodeScalars.allSatisfy(\.isASCII) else {
        return nil
      }
      return Data(base64Encoded: compact)
    }
  }

#endif
