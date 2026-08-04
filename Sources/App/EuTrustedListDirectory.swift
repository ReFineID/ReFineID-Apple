#if os(macOS)

  import CardCore
  import Foundation
  import Security

  /// The EU trust infrastructure's answer to "who is a qualified
  /// time-stamp service": the European Commission's list of trusted
  /// lists, and the national lists it points to (ETSI TS 119 612).
  internal enum EuTrustedListDirectory {
    /// Every certificate identifying a granted qualified time-stamp
    /// service.
    internal struct Identities: Sendable {
      internal let certificates: Set<Data>

      /// Whether every national XML list named by the index was read.
      ///
      /// An incomplete result can prove membership, but absence from
      /// it proves nothing.
      internal let isComplete: Bool
    }

    /// One authenticated national-list read.
    private struct NationalSuccess: Sendable {
      let certificates: [Data]
      let validUntil: Date
    }

    /// One national-list fetch, kept explicit so one failed member
    /// does not discard identities proved by the others.
    private enum NationalResult: Sendable {
      /// One list was fetched and parsed.
      case certificates(NationalSuccess)

      /// One list could not be authenticated, fetched, or parsed.
      case failed
    }

    /// One complete directory read and its earliest signed expiry.
    private struct DirectoryRead: Sendable {
      let identities: Identities
      let validUntil: Date
    }

    /// A malformed or empty directory cannot decide qualification.
    internal enum Failure: Error {
      /// The list of lists did not point to a national XML list.
      case emptyDirectory

      /// An HTTP answer did not carry usable XML bytes.
      case unusableResponse
    }

    /// Serializes and bounds refreshes of the legal-status directory.
    internal actor Cache {
      /// The last completed read and when it happened.
      private var stored: (read: DirectoryRead, fetchedAt: Date)?

      /// A recent read, or one fresh walk of the directory.
      internal func identities() async throws -> Identities {
        let now = Date()
        if let stored,
          EuTrustedListDirectory.mayReuse(
            fetchedAt: stored.fetchedAt,
            validUntil: stored.read.validUntil,
            at: now
          )
        {
          return stored.read.identities
        }
        let fresh = try await freshTimestampIdentities()
        if EuTrustedListDirectory.isCacheable(fresh.identities) {
          self.stored = (fresh, Date())
        } else {
          self.stored = nil
        }
        return fresh.identities
      }
    }

    /// Where the European Commission publishes the list of trusted
    /// lists.
    internal static let listOfLists = "https://ec.europa.eu/tools/lotl/eu-lotl.xml"

    /// SHA-256 fingerprints of the six LOTL-signing certificates in
    /// Official Journal notice C/2026/1944 of 15 April 2026.
    private static let officialJournalFingerprints: Set<Data> = {
      let encoded = [
        "wGQcT31WxDGxySR0Lbf86cHu99f9ISETonaEhrOrzcU=",
        "4KYg+7Z0c2K7kzrEQWnWdqVTREcWz18xYF8SoiuDlrE=",
        "334pNgw0srjW1fQDJcHU0SyZIs7NM7dAdnSnSys8oeU=",
        "tj1BZ0TnCYv57CyqWWqTvCRo43+ChLpl7MBhcRvLqhg=",
        "I2ED8DqAMa6PR/kFm/jeOFZM2/6+3eSll9UPiYCqZTs=",
        "0gZP3XD2mC3MUWuG2dXFauqTlBfGJLLkeMCyneVPhHQ=",
      ]
      let decoded = encoded.compactMap { Data(base64Encoded: $0) }
      precondition(decoded.count == encoded.count)
      return Set(decoded)
    }()

    /// The service type of a qualified time-stamping service.
    private static let qualifiedTimestampType =
      "http://uri.etsi.org/TrstSvc/Svctype/TSA/QTST"

    /// The status of a service currently granted.
    private static let grantedStatus =
      "http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted"

    /// A trusted-list result is reused across the signature and its
    /// archive timestamp, but not kept as a long-lived legal answer.
    private static let cacheLifetime: TimeInterval = 3_600

    /// National lists are measured in megabytes; an error page or an
    /// unbounded answer is not a trusted list.
    private static let maximumListBytes = 16_777_216

    /// XML is parsed without loading any external entity or resource.
    internal static let xmlOptions: XMLNode.Options = [
      .nodeLoadExternalEntitiesNever,
      .nodePreserveWhitespace,
    ]

    /// The one process-wide, actor-isolated cache.
    private static let cache = Cache()

    /// Whether both the local cache and signed validity windows are open.
    internal static func mayReuse(
      fetchedAt: Date,
      validUntil: Date,
      at validationTime: Date
    ) -> Bool {
      validationTime >= fetchedAt
        && validationTime < validUntil
        && validationTime < fetchedAt.addingTimeInterval(Self.cacheLifetime)
    }

    /// Only a complete legal-status answer may survive for cache reuse.
    internal static func isCacheable(_ identities: Identities) -> Bool {
      identities.isComplete
    }

    /// Reads the whole directory.
    ///
    /// The list of lists first, then every national list, in
    /// parallel. A national list that cannot be fetched or parsed
    /// contributes nothing rather than failing the walk - but an
    /// unreachable list of lists fails it, because an empty answer
    /// would read as "nobody is qualified".
    internal static func qualifiedTimestampIdentities() async throws -> Identities {
      try await Self.cache.identities()
    }

    /// Reads the directory without consulting the cache.
    private static func freshTimestampIdentities() async throws -> DirectoryRead {
      let index = try await Self.fetch(Self.listOfLists)
      let verifiedIndex = try TrustedListXmlSignature.verify(
        index,
        trusting: .sha256Fingerprints(Self.officialJournalFingerprints),
        at: Date()
      )
      let pointers = try Self.trustedListPointers(in: index)
      guard !pointers.isEmpty else { throw Failure.emptyDirectory }
      var certificates: Set<Data> = []
      var complete = true
      var validUntil = verifiedIndex.nextUpdate
      let results = await Self.mapRetryingFailures(
        pointers,
        maximumConcurrency: Self.maximumConcurrentNationalLists,
        isFailure: { result in
          if case .failed = result { return true }
          return false
        },
        operation: { pointer in
          await Self.nationalResult(for: pointer)
        }
      )
      for result in results {
        switch result {
        case .certificates(let success):
          certificates.formUnion(success.certificates)
          validUntil = min(validUntil, success.validUntil)
        case .failed:
          complete = false
        }
      }
      guard validUntil > Date() else { throw Failure.unusableResponse }
      return DirectoryRead(
        identities: Identities(
          certificates: certificates,
          isComplete: complete
        ),
        validUntil: validUntil
      )
    }

    /// Fetches and authenticates one exact LOTL pointer.
    private static func nationalResult(
      for pointer: TrustedListPointer
    ) async -> NationalResult {
      do {
        let list = try await Self.fetch(pointer.location)
        let verified = try TrustedListXmlSignature.verify(
          list,
          trusting: .certificates(pointer.signingCertificates),
          at: Date()
        )
        return .certificates(
          NationalSuccess(
            certificates: try Self.qualifiedTimestampCertificates(in: list),
            validUntil: verified.nextUpdate
          )
        )
      } catch {
        return .failed
      }
    }

    /// The identity certificates of every granted qualified
    /// time-stamp service in one national list.
    ///
    /// A service announces its type, its status, and the certificates
    /// that identify it; only the granted qualified time-stamp type
    /// contributes here.
    internal static func qualifiedTimestampCertificates(
      in list: Data
    ) throws -> [Data] {
      let document = try XMLDocument(data: list, options: Self.xmlOptions)
      let services = try document.nodes(
        forXPath: "//*[local-name()='TSPService']"
      )
      var found: [Data] = []
      for service in services {
        guard
          try Self.serviceValue(in: service, named: "ServiceTypeIdentifier")
            == Self.qualifiedTimestampType,
          try Self.serviceValue(in: service, named: "ServiceStatus")
            == Self.grantedStatus
        else { continue }
        let nodes = try service.nodes(
          forXPath: "./*[local-name()='ServiceInformation']"
            + "/*[local-name()='ServiceDigitalIdentity']"
            + "//*[local-name()='X509Certificate']"
        )
        guard !nodes.isEmpty else { throw Failure.unusableResponse }
        for node in nodes {
          guard
            let text = node.stringValue,
            let der = Self.strictBase64(text),
            SecCertificateCreateWithData(nil, der as CFData) != nil
          else { throw Failure.unusableResponse }
          found.append(der)
        }
      }
      return found
    }

    /// Decodes XML base64 without accepting arbitrary non-base64 bytes.
    private static func strictBase64(_ encoded: String) -> Data? {
      let xmlWhitespace: Set<Character> = [" ", "\t", "\n", "\r"]
      let compact = encoded.filter { character in
        !xmlWhitespace.contains(character)
      }
      guard compact.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
      return Data(base64Encoded: compact)
    }

    /// The first named element's text under a node - in a TSPService,
    /// that is the current service information's, because history
    /// entries follow it in document order.
    private static func serviceValue(
      in node: XMLNode,
      named element: String
    ) throws -> String? {
      try node.nodes(
        forXPath: "./*[local-name()='ServiceInformation']"
          + "/*[local-name()='\(element)']"
      )
      .first?.stringValue
    }

    /// One list, fetched whole.
    private static func fetch(_ location: String) async throws -> Data {
      do {
        return try await SigningNetwork.get(
          location,
          maximumBytes: Self.maximumListBytes,
          endpoint: .certificateMaterial
        )
      } catch SigningNetwork.Failure.httpStatus,
        SigningNetwork.Failure.unusableBody
      {
        throw Failure.unusableResponse
      }
    }
  }

#endif
