#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation
  import os
  import RappEngine
  /// Single-use synchronous facade for CryptoTokenKit and registry callbacks.
  ///
  /// The blocking boundary contains no protocol logic; an actor-owned RAPP
  /// coordinator performs the authenticated asynchronous exchange.
  public final class RappPersistentRequesterClient: @unchecked Sendable {

    // MARK: Nested Types

    private struct State: Sendable {
      var started = false
      var operationStarted = false
      var completed = false
      var coordinator: RappConnectionCoordinator?
      #if REFINEID_SLIM_RELAY
        var slimSession: SignRelaySession?
        var slimRequestID: UUID?
      #endif
      var response: RappRequesterResponse?
      var error: RappRequesterClientError?
    }

    // MARK: Properties

    private let displayName: String
    private let policy: RappRequesterPolicy
    private let vault: RappDeviceVault
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let completed = DispatchSemaphore(value: 0)
    #if REFINEID_SLIM_RELAY
      private let pendingSlimRequest = OSAllocatedUnfairLock<Data?>(initialState: nil)
    #endif
    private var operation: RappRequesterOperation?

    private lazy var relay = PersistentRelaySession(
      role: .host,
      displayName: displayName
    ) { [weak self] event in
      self?.receive(event)
    }

    private lazy var transport = RappClosureFrameTransport(
      sender: { [weak self] frame in
        guard let self else { throw RappRequesterClientError.transport }
        try relay.send(frame)
      },
      closer: { [weak self] in
        self?.relay.cancel()
      }
    )

    // MARK: Lifecycle

    /// Builds a one-shot client that connects over the persistent relay
    /// and resolves its pair from the vault.
    public init(
      displayName: String,
      policy: RappRequesterPolicy = .interactive,
      vault: RappDeviceVault = RappDeviceVault()
    ) {
      self.displayName = displayName
      self.policy = policy
      self.vault = vault
    }

    // MARK: Functions

    /// Runs one operation and blocks the caller until it resolves.
    ///
    /// The wait is bounded by the policy's synchronous timeout. A client
    /// performs at most one operation; a second call fails as a protocol
    /// error.
    public func perform(_ operation: RappRequesterOperation) throws -> RappRequesterResponse {
      let accepted = state.withLock { state -> Bool in
        guard !state.started else { return false }
        state.started = true
        return true
      }
      guard accepted else { throw RappRequesterClientError.protocolFailure }
      self.operation = operation
      relay.start()

      guard completed.wait(timeout: .now() + policy.synchronousWaitTimeout) == .success else {
        let coordinator = state.withLock { state -> RappConnectionCoordinator? in
          guard !state.completed else { return state.coordinator }
          state.completed = true
          state.error = .timedOut
          return state.coordinator
        }
        Task { await coordinator?.close() }
        relay.cancel()
        throw RappRequesterClientError.timedOut
      }

      relay.cancel()
      return try state.withLock { state in
        if let response = state.response { return response }
        throw state.error ?? RappRequesterClientError.transport
      }
    }

    private func receive(_ event: PersistentRelayEvent) {
      switch event {
      case .connected:
        Task { await establish() }
      case .frame(let frame):
        #if REFINEID_SLIM_RELAY
          Task { await receiveSlim(frame) }
        #else
          let coordinator = state.withLock { $0.coordinator }
          Task { await coordinator?.receive(frame) }
        #endif
      case .closed:
        let coordinator = state.withLock { $0.coordinator }
        Task {
          await coordinator?.transportClosed()
          finish(error: .transport)
        }
      }
    }

    private func establish() async {
      do {
        let pairIDs = try vault.activePairIDs()
        guard !pairIDs.isEmpty else {
          finish(error: .noActivePair)
          return
        }
        let pairID: Data
        if let selected = try vault.selectedPairID() {
          guard pairIDs.contains(selected) else {
            try vault.clearSelectedPair()
            finish(error: .noSelectedPair)
            return
          }
          pairID = selected
        } else if pairIDs.count == 1 {
          pairID = pairIDs[0]
          try vault.selectPair(pairID: pairID)
        } else {
          finish(error: .noSelectedPair)
          return
        }
        let pair = try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
        #if REFINEID_SLIM_RELAY
          try await establishSlim(pair: pair)
          return
        #endif
        let coordinator = try RappConnectionCoordinator(
          role: .requester,
          pair: pair,
          vault: vault,
          transport: transport,
          maximumLifetimeMilliseconds: policy.maximumOperationLifetimeMilliseconds,
          liveness: policy.liveness
        )
        let installed = state.withLock { state -> Bool in
          guard state.coordinator == nil, !state.completed else { return false }
          state.coordinator = coordinator
          return true
        }
        guard installed else { return }

        Task { [weak self] in
          for await event in coordinator.events {
            await self?.receive(event, from: coordinator)
          }
        }
        await coordinator.start()
      } catch {
        finish(error: .protocolFailure)
      }
    }

    #if REFINEID_SLIM_RELAY
      /// Opens a slim session over the selected pairing and asks once.
      private func establishSlim(pair: RappPairRecord) async throws {
        guard let operation else {
          finish(error: .protocolFailure)
          return
        }
        let requestID = UUID()
        guard let request = SignRelayOperation.request(for: operation, id: requestID) else {
          finish(error: .unexpectedResult)
          return
        }
        let session = try SignRelaySession(role: .requester, pair: pair, vault: vault)
        let installed = state.withLock { state -> Bool in
          guard state.slimSession == nil, !state.completed else { return false }
          state.slimSession = session
          state.slimRequestID = requestID
          return true
        }
        guard installed else { return }
        pendingSlimRequest.withLock { $0 = try? request.encoded() }
        for frame in try await session.start().send {
          try relay.send(frame)
        }
      }

      /// Drives one frame through the slim session, and answers when the
      /// peer's message is the one this client asked for.
      private func receiveSlim(_ frame: Data) async {
        guard let session = state.withLock({ $0.slimSession }) else { return }
        let step: SignRelayStep
        do {
          step = try await session.receive(frame)
        } catch {
          finish(error: .transport)
          return
        }
        for outgoing in step.send {
          try? relay.send(outgoing)
        }
        if await session.isEstablished {
          await sendPendingSlimRequest(over: session)
        }
        guard
          let payload = step.payload,
          let answer = try? PersistentRelayMessage.decoded(payload),
          let operation
        else { return }
        guard let response = SignRelayOperation.response(from: answer, for: operation) else {
          finish(error: .unexpectedResult)
          return
        }
        finish(response: response)
      }

      /// Sends the one request this client carries, once the session can.
      private func sendPendingSlimRequest(over session: SignRelaySession) async {
        guard
          let encoded = pendingSlimRequest.withLock({ value -> Data? in
            defer { value = nil }
            return value
          })
        else { return }
        guard let sealed = try? await session.seal(encoded) else {
          finish(error: .transport)
          return
        }
        try? relay.send(sealed)
      }
    #endif

    private func receive(
      _ event: RappConnectionCoordinator.Event,
      from coordinator: RappConnectionCoordinator
    ) async {
      switch event {
      case .established:
        let shouldStart = state.withLock { state -> Bool in
          guard !state.operationStarted, !state.completed else { return false }
          state.operationStarted = true
          return true
        }
        guard shouldStart, let operation else { return }
        do {
          switch operation {
          case .readAuthenticationCertificate:
            try await coordinator.beginReadCertificate(
              signatureCertificate: false,
              expiresAfterMilliseconds: policy.maximumOperationLifetimeMilliseconds
            )
          case .readSignatureCertificate:
            try await coordinator.beginReadCertificate(
              signatureCertificate: true,
              expiresAfterMilliseconds: policy.maximumOperationLifetimeMilliseconds
            )
          case .browserAuthentication(let context, let keyProfile, let algorithm, let digest):
            try await coordinator.beginBrowserAuthentication(
              origin: context,
              keyProfile: keyProfile,
              algorithm: algorithm,
              digest: digest,
              expiresAfterMilliseconds: policy.maximumOperationLifetimeMilliseconds
            )
          case .documentSigning(let documentName, let keyProfile, let algorithm, let digest):
            try await coordinator.beginSignDocument(
              documentName: documentName,
              keyProfile: keyProfile,
              algorithm: algorithm,
              digest: digest,
              expiresAfterMilliseconds: policy.maximumOperationLifetimeMilliseconds
            )
          }
        } catch {
          await coordinator.close()
          finish(error: .protocolFailure)
        }

      case .completed(_, let result):
        let response: RappRequesterResponse?
        switch (operation, result.kind) {
        case (.readAuthenticationCertificate, .certificate):
          response = result.bytes.isEmpty ? nil : .authenticationCertificate(result.bytes)
        case (.readSignatureCertificate, .certificate):
          response = result.bytes.isEmpty ? nil : .signatureCertificate(result.bytes)
        case (.browserAuthentication, .signature):
          response = result.bytes.isEmpty ? nil : .signature(result.bytes)
        case (.documentSigning, .signature):
          response = result.bytes.isEmpty ? nil : .signature(result.bytes)
        default:
          response = nil
        }
        await coordinator.close()
        if let response {
          finish(response: response)
        } else {
          finish(error: .unexpectedResult)
        }

      case .terminal(_, _, let reason):
        await coordinator.close()
        finish(error: .terminal(reason))

      case .closed:
        finish(error: .transport)

      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
        .executeCardCommand, .advisoryCancellation, .operationFinished,
        .peerBusy, .peerUnknownOperation:
        await coordinator.close()
        finish(error: .protocolFailure)
      }
    }

    private func finish(
      response: RappRequesterResponse? = nil,
      error: RappRequesterClientError? = nil
    ) {
      let shouldSignal = state.withLock { state -> Bool in
        guard !state.completed else { return false }
        state.completed = true
        state.response = response
        state.error = error
        return true
      }
      if shouldSignal { completed.signal() }
    }
  }
#endif
