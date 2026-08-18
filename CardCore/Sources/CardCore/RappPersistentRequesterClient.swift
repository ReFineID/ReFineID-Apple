#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation
  import os
  import RappEngine
  /// Timing policy for one requester-side RAPP operation: the lifetime the
  /// operation is granted, the bound on the synchronous wait, and the pacing
  /// of liveness probes on the established channel.
  public struct RappRequesterPolicy: Sendable, Equatable {
    /// Operation lifetime granted to the RAPP runtime and sent as the
    /// expiry when the operation begins.
    public let maximumOperationLifetimeMilliseconds: UInt64
    /// Longest time ``RappPersistentRequesterClient/perform(_:)`` blocks
    /// before failing as timed out.
    public let synchronousWaitTimeout: TimeInterval
    /// Liveness probing configuration for the established channel.
    public let liveness: RappOperationDriver.Liveness

    /// Composes a policy from explicit timing values.
    public init(
      maximumOperationLifetimeMilliseconds: UInt64,
      synchronousWaitTimeout: TimeInterval,
      liveness: RappOperationDriver.Liveness
    ) {
      self.maximumOperationLifetimeMilliseconds = maximumOperationLifetimeMilliseconds
      self.synchronousWaitTimeout = synchronousWaitTimeout
      self.liveness = liveness
    }

    /// Provisional interactive policy.
    ///
    /// It is injectable so measured transport behavior can revise policy
    /// without adding UI timing heuristics.
    public static let interactive = Self(
      maximumOperationLifetimeMilliseconds: 120_000,
      synchronousWaitTimeout: 125,
      liveness: .init(
        baseIntervalMilliseconds: 5_000,
        responseTimeoutMilliseconds: 3_000,
        maximumIntervalMilliseconds: 60_000,
        maximumJitterMilliseconds: 500,
        maximumMisses: 3
      )
    )
  }

  /// A card operation the requester asks the paired proxy to perform.
  public enum RappRequesterOperation: Sendable, Equatable {
    case readAuthenticationCertificate
    case readSignatureCertificate
    case browserAuthentication(
      displayContext: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    )
    case documentSigning(
      documentName: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    )
  }

  /// The authenticated payload a completed requester operation yields.
  public enum RappRequesterResponse: Sendable, Equatable {
    case authenticationCertificate(Data)
    case signatureCertificate(Data)
    case signature(Data)
  }

  /// Why a requester operation ended without a response.
  public enum RappRequesterClientError: Error, Sendable, Equatable {
    case noActivePair
    case noSelectedPair
    case transport
    case protocolFailure
    case terminal(RappOperationDriver.TerminalReason?)
    case timedOut
    case unexpectedResult
  }

  /// Single-use synchronous facade for CryptoTokenKit and registry callbacks.
  ///
  /// The blocking boundary contains no protocol logic; an actor-owned RAPP
  /// coordinator performs the authenticated asynchronous exchange.
  public final class RappPersistentRequesterClient: @unchecked Sendable {
    private struct State: Sendable {
      var started = false
      var operationStarted = false
      var completed = false
      var coordinator: RappConnectionCoordinator?
      var response: RappRequesterResponse?
      var error: RappRequesterClientError?
    }

    private let displayName: String
    private let policy: RappRequesterPolicy
    private let vault: RappDeviceVault
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let completed = DispatchSemaphore(value: 0)
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
        let coordinator = state.withLock { $0.coordinator }
        Task { await coordinator?.receive(frame) }
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
