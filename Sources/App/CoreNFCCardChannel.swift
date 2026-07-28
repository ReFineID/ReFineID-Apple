#if canImport(CoreNFC) && os(iOS)

  import CardCore
  @preconcurrency import CoreNFC
  import Foundation

  /// Moves APDUs over one connected Core NFC ISO 7816 tag.
  ///
  /// Core NFC owns the first priming field. CryptoTokenKit is not opened
  /// until this channel has finished PACE and read the identity metadata,
  /// so the token extension cannot race the app for the same card session.
  @available(iOS 26.0, *)
  internal final class CoreNFCCardChannel: CardChannel, @unchecked Sendable {
    /// Carries callback state across a blocking semaphore boundary.
    private final class ResultBox: @unchecked Sendable {
      private let lock = NSLock()
      private var result: Result<Data, any Error>?

      func set(_ result: Result<Data, any Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
      }

      func get() -> Result<Data, any Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
      }
    }

    /// APDU callback budget in seconds.
    private static let commandTimeoutSeconds = 10

    /// One APDU callback gets this long before the transport is failed.
    private static let commandTimeout: DispatchTimeInterval =
      .seconds(CoreNFCCardChannel.commandTimeoutSeconds)

    /// Plain Core NFC responses can carry the normal read chunk.
    internal var readChunkLength: ReadChunkLength {
      .plain
    }

    private let tag: any NFCISO7816Tag

    /// Historical bytes for Type A, application data for Type B.
    internal var identification: Data {
      if let historical = tag.historicalBytes, !historical.isEmpty {
        return historical
      }
      if let applicationData = tag.applicationData, !applicationData.isEmpty {
        return applicationData
      }
      return Data()
    }

    internal init(tag: any NFCISO7816Tag) {
      self.tag = tag
    }

    /// Sends one command synchronously from the dedicated card queue.
    internal func transmit(_ payload: Data) throws -> Data {
      guard let command = NFCISO7816APDU(data: payload) else {
        throw CardOperationError.malformedResponse
      }
      let result = ResultBox()
      let semaphore = DispatchSemaphore(value: 0)
      let started = ContinuousClock.now
      tag.sendCommand(apdu: command) { data, sw1, sw2, error in
        if let error {
          result.set(.failure(error))
        } else {
          var response = data
          response.append(sw1)
          response.append(sw2)
          result.set(.success(response))
        }
        semaphore.signal()
      }
      guard semaphore.wait(timeout: .now() + Self.commandTimeout) == .success else {
        ExtensionTrace.append(
          CardExchangeTrace.line(
            request: payload,
            response: nil,
            elapsed: started.duration(to: ContinuousClock.now)))
        throw CoreNFCPrimeSession.Failure.commandTimedOut
      }
      let elapsed = started.duration(to: ContinuousClock.now)
      switch result.get() {
      case .success(let response):
        ExtensionTrace.append(
          CardExchangeTrace.line(request: payload, response: response, elapsed: elapsed))
        return response
      case .failure(let error):
        ExtensionTrace.append(
          CardExchangeTrace.line(request: payload, response: nil, elapsed: elapsed))
        throw error
      case nil:
        throw CardOperationError.malformedResponse
      }
    }
  }

#endif
