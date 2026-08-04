#if os(macOS)

  import Foundation

  /// Fetches a timestamp and the public certificate-status material an
  /// archival signature needs.
  ///
  /// What travels is a digest, certificate identifier, or public
  /// certificate material - never a key, PIN, or document byte. TLS is
  /// supplied by the operating system.
  internal enum SigningNetwork {
    /// Why a fetch could not be used.
    internal enum Failure: Error, Equatable {
      /// The address did not parse.
      case badAddress

      /// The service answered with an error status.
      case httpStatus(Int)

      /// Basic credentials would cross an unauthenticated connection.
      case insecureCredentials

      /// One exchange tried to follow too many redirects.
      case redirectLimitExceeded

      /// A certificate-published address does not name the public Internet.
      case unsafeAddress

      /// A redirect changed a protected endpoint or left HTTP(S).
      case unsafeRedirect

      /// The answer was empty or beyond the accepted size.
      case unusableBody
    }

    /// Bytes accepted from a timestamp or revocation service.
    private static let maximumResponseBytes = 65_536

    /// Bytes accepted from a certificate revocation list, which is a
    /// published document rather than a per-request answer.
    private static let maximumListBytes = 1_048_576

    /// Seconds any one exchange may take.
    private static let timeout: TimeInterval = 30

    /// HTTP statuses that carry a usable body.
    internal static let successStatuses = 200..<300

    /// An ephemeral session whose DNS answers are validated by the system.
    internal static func validatedSessionConfiguration()
      -> URLSessionConfiguration
    {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.requiresDNSSECValidation = true
      return configuration
    }

    /// POSTs a DER request and answers the DER response.
    ///
    /// `credentials`, when present, become an HTTP Basic header - the
    /// only shape commercial authorities ask for.
    internal static func post(
      _ body: Data,
      to address: String,
      contentType: String,
      credentials: (username: String, password: String)?,
      endpoint: Endpoint
    ) async throws -> Data {
      let request = try Self.postRequest(
        body,
        to: address,
        contentType: contentType,
        credentials: credentials,
        endpoint: endpoint
      )
      let protected = try Self.protectedRequest(of: request, for: endpoint)
      return try await Self.perform(
        protected,
        limit: Self.maximumResponseBytes,
        endpoint: endpoint,
        carriesCredentials: credentials != nil
      )
    }

    /// Builds one timestamp or OCSP request without sending it.
    ///
    /// Kept as a direct test boundary for the scheme and credential
    /// rules that must hold before URLSession sees the request.
    internal static func postRequest(
      _ body: Data,
      to address: String,
      contentType: String,
      credentials: (username: String, password: String)?,
      endpoint: Endpoint
    ) throws -> URLRequest {
      let url = try Self.httpUrl(address, for: endpoint)
      if credentials != nil, url.scheme?.lowercased() != "https" {
        throw Failure.insecureCredentials
      }
      var request = URLRequest(url: url, timeoutInterval: Self.timeout)
      request.httpMethod = "POST"
      request.setValue(contentType, forHTTPHeaderField: "Content-Type")
      request.httpBody = body
      if let credentials {
        let pair = "\(credentials.username):\(credentials.password)"
        let encoded = Data(pair.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
      }
      return request
    }

    /// GETs one public endpoint with a caller-defined body cap.
    ///
    /// Two public redirects are followed for certificate material. This covers
    /// the official Danish TSL's canonical-host hop and media-host hop; longer
    /// chains are refused because an untrusted URL should not be a tour.
    internal static func get(
      _ address: String,
      maximumBytes: Int,
      endpoint: Endpoint
    ) async throws -> Data {
      guard maximumBytes > 0 else { throw Failure.unusableBody }
      let url = try Self.httpUrl(address, for: endpoint)
      let request = URLRequest(url: url, timeoutInterval: Self.timeout)
      let protected = try Self.protectedRequest(
        of: request,
        for: endpoint
      )
      return try await Self.perform(
        protected,
        limit: maximumBytes,
        endpoint: endpoint,
        carriesCredentials: false
      )
    }

    /// GETs certificate or revocation material with its existing size cap.
    internal static func get(
      _ address: String,
      allowingListSize: Bool
    ) async throws -> Data {
      let limit = allowingListSize ? Self.maximumListBytes : Self.maximumResponseBytes
      return try await Self.get(
        address,
        maximumBytes: limit,
        endpoint: .certificateMaterial
      )
    }

    /// Runs one exchange and checks its status and size.
    private static func perform(
      _ request: URLRequest,
      limit: Int,
      endpoint: Endpoint,
      carriesCredentials: Bool
    ) async throws -> Data {
      let configuration = Self.validatedSessionConfiguration()
      configuration.httpCookieStorage = nil
      configuration.urlCache = nil
      configuration.httpAdditionalHeaders = ["Accept": "*/*"]
      configuration.timeoutIntervalForRequest = Self.timeout
      configuration.timeoutIntervalForResource = Self.timeout
      let collector = BoundedResponseCollector(
        initial: request,
        endpoint: endpoint,
        carriesCredentials: carriesCredentials,
        limit: limit
      )
      let session = URLSession(
        configuration: configuration,
        delegate: collector,
        delegateQueue: nil
      )
      defer { session.finishTasksAndInvalidate() }
      let data = try await collector.response(using: session, request: request)
      guard !data.isEmpty, data.count <= limit else {
        throw Failure.unusableBody
      }
      return data
    }
  }

#endif
