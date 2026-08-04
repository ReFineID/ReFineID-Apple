#if os(macOS)

  import Foundation

  /// The two kinds of fetch an archival signature needs: a timestamp
  /// from an authority, and the public evidence that proves a chain.
  ///
  /// These are the only network operations the app performs, and what
  /// travels is a digest or a certificate identifier - never a key, a
  /// PIN, or one byte of the document. TLS is the operating system's;
  /// this speaks only HTTP semantics on top of it.
  internal enum SigningNetwork {
    /// Why a fetch could not be used.
    internal enum Failure: Error, Equatable {
      /// The address did not parse.
      case badAddress

      /// The service answered with an error status.
      case httpStatus(Int)

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
    private static let successStatuses = 200..<300

    /// POSTs a DER request and answers the DER response.
    ///
    /// `credentials`, when present, become an HTTP Basic header - the
    /// only shape commercial authorities ask for.
    internal static func post(
      _ body: Data,
      to address: String,
      contentType: String,
      credentials: (username: String, password: String)?
    ) async throws -> Data {
      guard let url = URL(string: address), url.scheme?.hasPrefix("http") == true
      else {
        throw Failure.badAddress
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
      return try await Self.perform(request, limit: Self.maximumResponseBytes)
    }

    /// GETs a certificate or revocation list.
    ///
    /// One redirect is followed, which is what certificate authorities
    /// publishing through a CDN require; a chain of them is refused,
    /// because an issuer URL should not be a tour.
    internal static func get(
      _ address: String,
      allowingListSize: Bool
    ) async throws -> Data {
      guard let url = URL(string: address), url.scheme?.hasPrefix("http") == true
      else {
        throw Failure.badAddress
      }
      let limit = allowingListSize ? Self.maximumListBytes : Self.maximumResponseBytes
      let request = URLRequest(url: url, timeoutInterval: Self.timeout)
      return try await Self.perform(request, limit: limit)
    }

    /// Runs one exchange and checks its status and size.
    private static func perform(
      _ request: URLRequest,
      limit: Int
    ) async throws -> Data {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpCookieStorage = nil
      configuration.urlCache = nil
      configuration.httpAdditionalHeaders = ["Accept": "*/*"]
      let session = URLSession(configuration: configuration)
      defer { session.finishTasksAndInvalidate() }
      let (data, response) = try await session.data(for: request)
      if let http = response as? HTTPURLResponse,
        !Self.successStatuses.contains(http.statusCode)
      {
        throw Failure.httpStatus(http.statusCode)
      }
      guard !data.isEmpty, data.count <= limit else {
        throw Failure.unusableBody
      }
      return data
    }
  }

#endif
