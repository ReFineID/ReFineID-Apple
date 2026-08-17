#if canImport(ReFineIDRapp)
  import Foundation
  import ReFineIDRapp

  /// The sole byte-transport capability required by RAPP.
  ///
  /// Implementations must preserve frame boundaries and report successful
  /// release by returning from ``send(_:)``. They must not parse, log, retry,
  /// or reinterpret frames.
  public protocol RappFrameTransport: Sendable {
    func send(_ frame: Data) async throws
    func close() async
  }

  /// Runs card operations over the completed pairing's live channel. The
  /// channel is already authenticated when this coordinator is built; every
  /// close ends the session and the pairing together.
  public actor RappConnectionCoordinator {
    /// Why the connection closed.
    public enum CloseReason: Sendable, Equatable {
      case operation(RappOperationDriver.CloseReason)
      case transportFailure
      case localRequest
    }

    /// One semantic, authenticated event surfaced by the connection.
    public enum Event: Sendable, Equatable {
      case established
      case inspectPrerequisites(
        operationID: Data,
        operation: RappOperationDriver.Operation
      )
      case awaitUserApproval(
        operationID: Data,
        operation: RappOperationDriver.Operation
      )
      case executeSafeRead(
        operationID: Data,
        operation: RappOperationDriver.Operation
      )
      case executeCardCommand(
        operationID: Data,
        operation: RappOperationDriver.Operation
      )
      case completed(
        operationID: Data,
        result: RappOperationDriver.Result
      )
      case terminal(
        operationID: Data?,
        state: String?,
        reason: RappOperationDriver.TerminalReason?
      )
      case advisoryCancellation(operationID: Data?)
      case operationFinished(operationID: Data?)
      case peerReserved(operationID: Data?)
      case peerUnknownOperation(operationID: Data?)
      case closed(CloseReason)
    }

    private enum Phase: Equatable {
      case operating
      case closed
    }

    /// Connection events in order; the stream finishes after `closed`.
    nonisolated public let events: AsyncStream<Event>

    private let transport: any RappFrameTransport
    private let liveness: RappOperationDriver.Liveness
    private let clock: RappPlatformClock
    private let continuation: AsyncStream<Event>.Continuation
    private let operation: RappOperationDriver
    private var phase = Phase.operating
    private var started = false
    private var livenessTask: Task<Void, Never>?

    /// Enters the operation runtime on the completed pairing's channel;
    /// ``start()`` reports the session established and arms liveness.
    public init(
      role: RappOperationDriver.Role,
      pairing: RappPairingBridge,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      maximumLifetimeMilliseconds: UInt64,
      liveness: RappOperationDriver.Liveness,
      clock: RappPlatformClock = RappPlatformClock()
    ) throws {
      self.transport = transport
      self.liveness = liveness
      self.clock = clock
      self.operation = try RappOperationDriver(
        role: role,
        pairing: pairing,
        vault: vault,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds,
        liveness: liveness,
        entropy: RappPlatformEntropy(),
        clock: clock
      )

      var capturedContinuation: AsyncStream<Event>.Continuation?
      self.events = AsyncStream { capturedContinuation = $0 }
      guard let capturedContinuation else {
        preconditionFailure("AsyncStream did not provide a continuation")
      }
      self.continuation = capturedContinuation
    }

    deinit {
      livenessTask?.cancel()
      continuation.finish()
    }

    /// Reports the already-authenticated channel as the established session
    /// and arms the liveness schedule.
    public func start() async {
      guard phase == .operating, !started else { return }
      started = true
      continuation.yield(.established)
      let now = clock.monotonicMilliseconds()
      let (deadline, overflow) = now.addingReportingOverflow(
        liveness.baseIntervalMilliseconds
      )
      scheduleLiveness(at: overflow ? UInt64.max : deadline)
    }

    /// Delivers one complete frame received by the transport.
    public func receive(_ frame: Data) async {
      guard phase == .operating else { return }
      await handleOperation(await operation.receive(frame))
    }

    /// Starts an inspect-card operation with the given expiry window.
    public func beginInspectCard(expiresAfterMilliseconds: UInt64) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginInspectCard(
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Starts a read-identity operation with the given expiry window.
    public func beginReadIdentity(expiresAfterMilliseconds: UInt64) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginReadIdentity(
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Starts a read of the authentication or signature certificate.
    public func beginReadCertificate(
      signatureCertificate: Bool,
      expiresAfterMilliseconds: UInt64
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginReadCertificate(
          signatureCertificate: signatureCertificate,
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Starts a browser-authentication operation over a digest for an origin.
    public func beginBrowserAuthentication(
      origin: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginBrowserAuthentication(
          origin: origin,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest,
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Starts a sign-document operation over the digest of a named document.
    public func beginSignDocument(
      documentName: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginSignDocument(
          documentName: documentName,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest,
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Reports that proxy-side prerequisites for the operation are met.
    public func prerequisitesComplete(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.prerequisitesComplete(operationID: operationID))
    }

    /// Records the local user's approval of the pending operation.
    public func approve(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.approve(operationID: operationID))
    }

    /// Records the local user's denial of the pending operation.
    public func deny(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.deny(operationID: operationID))
    }

    /// Rejects the operation as malformed or unsupported on this device.
    public func requestInvalidOrUnsupported(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.requestInvalidOrUnsupported(
          operationID: operationID
        ))
    }

    /// Reports that the local retry policy refused to run the operation.
    public func retryRefused(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.retryRefused(operationID: operationID))
    }

    /// Reports that the card rejected the presented credential.
    public func credentialRejected(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.credentialRejected(operationID: operationID))
    }

    /// Reports that the card left the reader before the command was sent.
    public func cardRemovedBeforeTransmit(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.cardRemovedBeforeTransmit(
          operationID: operationID
        ))
    }

    /// Reports that the card command's completion could not be confirmed.
    public func cardCompletionAmbiguous(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.cardCompletionAmbiguous(
          operationID: operationID
        ))
    }

    /// Completes an inspection with PIN factory state and attempt counts.
    public func completeInspection(
      operationID: Data,
      pin1Factory: Bool,
      pin2Factory: Bool,
      pin1Attempts: UInt8?,
      pin2Attempts: UInt8?,
      pukAttempts: UInt8?
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeInspection(
          operationID: operationID,
          pin1Factory: pin1Factory,
          pin2Factory: pin2Factory,
          pin1Attempts: pin1Attempts,
          pin2Attempts: pin2Attempts,
          pukAttempts: pukAttempts
        ))
    }

    /// Completes an identity read with the holder's name and person ID.
    public func completeIdentity(
      operationID: Data,
      displayName: String,
      personID: String
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeIdentity(
          operationID: operationID,
          displayName: displayName,
          personID: personID
        ))
    }

    /// Completes a certificate read with the DER-encoded certificate.
    public func completeCertificate(operationID: Data, der: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeCertificate(
          operationID: operationID,
          der: der
        ))
    }

    /// Completes a signature operation with the raw signature bytes.
    public func completeSignature(operationID: Data, signature: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeSignature(
          operationID: operationID,
          signature: signature
        ))
    }

    /// Runs one liveness poll with the given scheduling jitter.
    public func pollLiveness(jitterMilliseconds: Int64) async {
      guard phase == .operating else { return }
      await handleOperation(
        await operation.pollLiveness(
          jitterMilliseconds: jitterMilliseconds
        ))
    }

    /// Reports that the transport closed without a local request.
    public func transportClosed() async {
      guard phase == .operating else { return }
      await handleOperation(await operation.transportClosed())
    }

    /// Closes the connection and finishes the event stream.
    public func close() async {
      guard phase == .operating else { return }
      _ = await operation.close()
      await finish(.localRequest)
    }

    private func operationDriver() throws -> RappOperationDriver {
      guard phase == .operating else {
        throw RappOperationDriver.LocalError.wrongPhase
      }
      return operation
    }

    private func handleOperation(_ commands: [RappOperationDriver.Command]) async {
      for command in commands where phase == .operating {
        switch command {
        case .send(let frame, let release):
          do {
            try await transport.send(frame)
            await handleOperation(await operation.frameReleased(release, succeeded: true))
          } catch {
            _ = await operation.transportClosed()
            await finish(.transportFailure)
          }

        case .inspectPrerequisites(let operationID, let operation):
          continuation.yield(
            .inspectPrerequisites(
              operationID: operationID,
              operation: operation
            ))
        case .awaitUserApproval(let operationID, let operation):
          continuation.yield(
            .awaitUserApproval(
              operationID: operationID,
              operation: operation
            ))
        case .executeSafeRead(let operationID, let operation):
          continuation.yield(
            .executeSafeRead(
              operationID: operationID,
              operation: operation
            ))
        case .executeCardCommand(let operationID, let operation):
          continuation.yield(
            .executeCardCommand(
              operationID: operationID,
              operation: operation
            ))
        case .completed(let operationID, let result):
          continuation.yield(.completed(operationID: operationID, result: result))
        case .terminal(let operationID, let state, let reason):
          continuation.yield(
            .terminal(
              operationID: operationID,
              state: state,
              reason: reason
            ))
        case .advisoryCancellation(let operationID):
          continuation.yield(.advisoryCancellation(operationID: operationID))
        case .operationFinished(let operationID):
          continuation.yield(.operationFinished(operationID: operationID))
        case .peerReserved(let operationID):
          continuation.yield(.peerReserved(operationID: operationID))
        case .peerUnknownOperation(let operationID):
          continuation.yield(.peerUnknownOperation(operationID: operationID))
        case .scheduleLiveness(let deadline):
          scheduleLiveness(at: deadline)
        case .closed(let reason):
          await finish(.operation(reason))
        }
      }
    }

    private func scheduleLiveness(at deadline: UInt64) {
      guard phase == .operating else { return }
      livenessTask?.cancel()

      let now = clock.monotonicMilliseconds()
      let delayMilliseconds = deadline > now ? deadline - now : 0
      let (convertedDelay, overflow) = delayMilliseconds.multipliedReportingOverflow(
        by: 1_000_000
      )
      let delayNanoseconds = overflow ? UInt64.max : convertedDelay
      let maximumJitter = min(
        liveness.maximumJitterMilliseconds,
        UInt64(Int64.max)
      )

      livenessTask = Task { [weak self] in
        do {
          try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
          return
        }
        guard !Task.isCancelled, let self else { return }

        var generator = SystemRandomNumberGenerator()
        let bound = Int64(maximumJitter)
        let jitter = Int64.random(in: -bound...bound, using: &generator)
        await pollLiveness(jitterMilliseconds: jitter)
      }
    }

    private func finish(_ reason: CloseReason) async {
      guard phase != .closed else { return }
      phase = .closed
      livenessTask?.cancel()
      livenessTask = nil
      await transport.close()
      continuation.yield(.closed(reason))
      continuation.finish()
    }
  }
#endif
