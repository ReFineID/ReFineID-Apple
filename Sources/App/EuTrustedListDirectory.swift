#if os(macOS)

  import CardCore
  import Foundation

  /// The EU trust infrastructure's answer to "who is a qualified
  /// time-stamp service": the European Commission's list of trusted
  /// lists, and the national lists it points to (ETSI TS 119 612).
  internal enum EuTrustedListDirectory {
    /// Every certificate identifying a granted qualified time-stamp
    /// service, and those certificates' public keys - the second
    /// catches a renewed certificate carrying the key the list knows.
    internal struct Identities {
      internal let certificates: Set<Data>
      internal let publicKeys: Set<Data>
    }

    /// Where the European Commission publishes the list of trusted
    /// lists.
    private static let listOfLists = "https://ec.europa.eu/tools/lotl/eu-lotl.xml"

    /// The service type of a qualified time-stamping service.
    private static let qualifiedTimestampType =
      "http://uri.etsi.org/TrstSvc/Svctype/TSA/QTST"

    /// The status of a service currently granted.
    private static let grantedStatus =
      "http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted"

    /// How long one list fetch may take before it is given up on.
    private static let fetchTimeout: TimeInterval = 30

    /// Reads the whole directory.
    ///
    /// The list of lists first, then every national list, in
    /// parallel. A national list that cannot be fetched or parsed
    /// contributes nothing rather than failing the walk - but an
    /// unreachable list of lists fails it, because an empty answer
    /// would read as "nobody is qualified".
    internal static func qualifiedTimestampIdentities() async throws -> Identities {
      let index = try await Self.fetch(Self.listOfLists)
      let locations = try Self.trustedListLocations(in: index)
      var certificates: Set<Data> = []
      await withTaskGroup(of: [Data].self) { group in
        for location in locations {
          group.addTask {
            guard let list = try? await Self.fetch(location) else { return [] }
            return (try? Self.qualifiedTimestampCertificates(in: list)) ?? []
          }
        }
        for await found in group {
          certificates.formUnion(found)
        }
      }
      let keys = certificates.compactMap { der in
        CertificateFacts(der: der)?.publicKeyBits
      }
      return Identities(certificates: certificates, publicKeys: Set(keys))
    }

    /// The national lists the list of lists points to, XML form only.
    private static func trustedListLocations(in list: Data) throws -> [String] {
      let document = try XMLDocument(data: list)
      let nodes = try document.nodes(
        forXPath: "//*[local-name()='OtherTSLPointer']"
          + "//*[local-name()='TSLLocation']"
      )
      return nodes.compactMap(\.stringValue).filter { location in
        location.hasSuffix(".xml") && location != Self.listOfLists
      }
    }

    /// The identity certificates of every granted qualified
    /// time-stamp service in one national list.
    ///
    /// A service announces its type, its status, and the certificates
    /// that identify it; only the granted qualified time-stamp type
    /// contributes here.
    private static func qualifiedTimestampCertificates(
      in list: Data
    ) throws -> [Data] {
      let document = try XMLDocument(data: list)
      let services = try document.nodes(
        forXPath: "//*[local-name()='TSPService']"
      )
      var found: [Data] = []
      for service in services {
        guard
          try Self.firstValue(in: service, named: "ServiceTypeIdentifier")
            == Self.qualifiedTimestampType,
          try Self.firstValue(in: service, named: "ServiceStatus")
            == Self.grantedStatus
        else { continue }
        let nodes = try service.nodes(
          forXPath: ".//*[local-name()='X509Certificate']"
        )
        for node in nodes {
          guard
            let text = node.stringValue,
            let der = Data(
              base64Encoded: text, options: .ignoreUnknownCharacters
            )
          else { continue }
          found.append(der)
        }
      }
      return found
    }

    /// The first named element's text under a node - in a TSPService,
    /// that is the current service information's, because history
    /// entries follow it in document order.
    private static func firstValue(
      in node: XMLNode,
      named element: String
    ) throws -> String? {
      try node.nodes(forXPath: ".//*[local-name()='\(element)']")
        .first?.stringValue
    }

    /// One list, fetched whole.
    private static func fetch(_ location: String) async throws -> Data {
      guard let url = URL(string: location) else {
        throw URLError(.badURL)
      }
      var request = URLRequest(url: url)
      request.timeoutInterval = Self.fetchTimeout
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForResource = Self.fetchTimeout
      let session = URLSession(configuration: configuration)
      defer { session.finishTasksAndInvalidate() }
      let (data, _) = try await session.data(for: request)
      return data
    }
  }

#endif
