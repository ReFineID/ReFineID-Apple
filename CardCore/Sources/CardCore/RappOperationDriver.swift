// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  /// Owns one established RAPP operation runtime and translates generated binding
  /// records into Sendable Apple-side values. It never performs card I/O itself.
  public actor RappOperationDriver {
    private enum OperationCommandKind {
      case inspect
      case approval
      case safeRead
      case cardCommand
    }

    private let bridge: RappOperationBridge
    private let entropy: RappPlatformEntropy
    private let clock: RappPlatformClock
    private var closed = false

    internal init(
      role: RappSessionDriver.Role,
      session: RappSessionBridge,
      vault: RappDeviceVault,
      maximumLifetimeMilliseconds: UInt64,
      liveness: Liveness,
      entropy: RappPlatformEntropy,
      clock: RappPlatformClock
    ) throws {
      self.entropy = entropy
      self.clock = clock
      let now = clock.monotonicMilliseconds()
      switch role {
      case .requester:
        bridge = try RappOperationBridge.beginRequester(
          session: session,
          vault: vault,
          maximumLifetimeMs: maximumLifetimeMilliseconds,
          liveness: liveness.binding,
          nowMs: now
        )
      case .proxy:
        bridge = try RappOperationBridge.beginProxy(
          session: session,
          vault: vault,
          maximumLifetimeMs: maximumLifetimeMilliseconds,
          liveness: liveness.binding,
          nowMs: now
        )
      }
    }

    /// Starts a requester inspection of card and PIN status.
    public func beginInspectCard(expiresAfterMilliseconds: UInt64) throws -> [Command] {
      try commands(
        bridge.beginInspectCard(
          operationId: entropy.operationID(),
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester read of the cardholder identity.
    public func beginReadIdentity(expiresAfterMilliseconds: UInt64) throws -> [Command] {
      try commands(
        bridge.beginReadIdentity(
          operationId: entropy.operationID(),
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester read of the authentication or signature certificate.
    public func beginReadCertificate(
      signatureCertificate: Bool,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginReadCertificate(
          operationId: entropy.operationID(),
          signatureCertificate: signatureCertificate,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester browser-authentication signature for the given origin.
    public func beginBrowserAuthentication(
      origin: String,
      keyProfile: KeyProfile,
      algorithm: SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginBrowserAuthentication(
          operationId: entropy.operationID(),
          origin: origin,
          keyProfile: keyProfile.binding,
          algorithm: algorithm.binding,
          digest: digest,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester document-signing operation for the named document.
    public func beginSignDocument(
      documentName: String,
      keyProfile: KeyProfile,
      algorithm: SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginSignDocument(
          operationId: entropy.operationID(),
          documentName: documentName,
          keyProfile: keyProfile.binding,
          algorithm: algorithm.binding,
          digest: digest,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Consumes one complete opaque frame received from the transport.
    public func receive(_ frame: Data) -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(
          bridge.receiveFrame(
            bytes: frame,
            nowMs: clock.monotonicMilliseconds()
          ))
      } catch {
        return protocolFailure()
      }
    }

    /// Marks bounded card-status and certificate prerequisites complete.
    public func prerequisitesComplete(operationID: Data) throws -> [Command] {
      try commands(bridge.prerequisitesComplete(operationId: operationID))
    }

    /// Approves exactly the request displayed by the authorizer UI.
    public func approve(operationID: Data) throws -> [Command] {
      try commands(
        bridge.approve(
          operationId: operationID,
          approvedAtMs: clock.monotonicMilliseconds()
        ))
    }

    /// Denies the exact request and emits a stable denial.
    public func deny(operationID: Data) throws -> [Command] {
      try commands(bridge.deny(operationId: operationID))
    }

    /// Rejects a request that is unsupported or contradicts the live card.
    public func requestInvalidOrUnsupported(operationID: Data) throws -> [Command] {
      try commands(bridge.requestInvalidOrUnsupported(operationId: operationID))
    }

    /// Reports that local retry policy refused the request.
    public func retryRefused(operationID: Data) throws -> [Command] {
      try commands(bridge.retryRefused(operationId: operationID))
    }

    /// Reports that the card rejected the presented credential.
    public func credentialRejected(operationID: Data) throws -> [Command] {
      try commands(
        bridge.credentialRejected(
          operationId: operationID,
          rejectedAtMs: clock.monotonicMilliseconds()
        ))
    }

    /// Reports that the card left the reader before the command was sent.
    public func cardRemovedBeforeTransmit(operationID: Data) throws -> [Command] {
      try commands(bridge.cardRemovedBeforeTransmit(operationId: operationID))
    }

    /// Reports that card completion could not be determined either way.
    public func cardCompletionAmbiguous(operationID: Data) throws -> [Command] {
      try commands(bridge.cardCompletionAmbiguous(operationId: operationID))
    }

    /// Completes an inspection with factory state and remaining attempt counts.
    public func completeInspection(
      operationID: Data,
      pin1Factory: Bool,
      pin2Factory: Bool,
      pin1Attempts: UInt8?,
      pin2Attempts: UInt8?,
      pukAttempts: UInt8?
    ) throws -> [Command] {
      try commands(
        bridge.completeInspection(
          operationId: operationID,
          pin1Factory: pin1Factory,
          pin2Factory: pin2Factory,
          pin1Attempts: pin1Attempts,
          pin2Attempts: pin2Attempts,
          pukAttempts: pukAttempts
        ))
    }

    /// Completes an identity read with the cardholder name and identifier.
    public func completeIdentity(
      operationID: Data,
      displayName: String,
      personID: String
    ) throws -> [Command] {
      try commands(
        bridge.completeIdentity(
          operationId: operationID,
          displayName: displayName,
          personId: personID
        ))
    }

    /// Completes a certificate read with DER bytes read from the card.
    public func completeCertificate(operationID: Data, der: Data) throws -> [Command] {
      try commands(bridge.completeCertificate(operationId: operationID, der: der))
    }

    /// Completes a signing operation with the card-produced signature.
    public func completeSignature(operationID: Data, signature: Data) throws -> [Command] {
      try commands(bridge.completeSignature(operationId: operationID, signature: signature))
    }

    /// Must be called only after the transport reports whether it released the
    /// corresponding frame.
    ///
    /// A failed release classifies all in-flight work as a closed or ambiguous
    /// session through the Rust engine.
    public func frameReleased(_ release: FrameRelease, succeeded: Bool) -> [Command] {
      guard !closed else { return [] }
      guard succeeded else { return transportClosed() }

      do {
        switch release {
        case .none:
          return []
        case .resultAcknowledgment(let operationID):
          let result = try bridge.acknowledgmentReleased(operationId: operationID)
          return [.completed(operationID: operationID, result: Result(result))]
        case .closeSession:
          closed = true
          return [.closed(.terminalFrameReleased)]
        }
      } catch {
        return protocolFailure()
      }
    }

    /// Advances authenticated liveness with fresh challenge bytes and the
    /// caller-generated jitter.
    public func pollLiveness(jitterMilliseconds: Int64) -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(
          bridge.pollLiveness(
            nowMs: clock.monotonicMilliseconds(),
            challenge: entropy.livenessChallenge(),
            jitterMs: jitterMilliseconds
          ))
      } catch {
        return protocolFailure()
      }
    }

    /// Closes the session after the transport reported closure.
    public func transportClosed() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = try? bridge.closeSession()
      return [.closed(.transportClosed)]
    }

    /// Closes the session at local request.
    public func close() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = try? bridge.closeSession()
      return [.closed(.localRequest)]
    }

    private func commands(_ action: RappBridgeAction) throws -> [Command] {
      if let frame = action.frame {
        let release: FrameRelease
        if action.kind == .resultAcknowledgment {
          guard let operationID = action.operationId else {
            throw LocalError.missingOperationIdentifier
          }
          release = .resultAcknowledgment(operationID: operationID)
        } else if action.closeSessionAfterSend {
          release = .closeSession
        } else {
          release = .none
        }
        return scheduled([.send(frame: frame, release: release)], for: action)
      }

      let operationID = action.operationId
      switch action.kind {
      case .inspectPrerequisites:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .inspect)],
          for: action
        )
      case .awaitUserApproval:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .approval)],
          for: action
        )
      case .executeSafeRead:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .safeRead)],
          for: action
        )
      case .executeCardCommand:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .cardCommand)],
          for: action
        )
      case .terminal, .cancelled:
        return scheduled(
          [
            .terminal(
              operationID: operationID,
              state: action.terminalState,
              reason: action.terminalReason.map(TerminalReason.init)
            )
          ], for: action)
      case .advisoryCancellation:
        return scheduled([.advisoryCancellation(operationID: operationID)], for: action)
      case .resultAcknowledged:
        return scheduled([.operationFinished(operationID: operationID)], for: action)
      case .peerBusy:
        return scheduled([.peerBusy(operationID: operationID)], for: action)
      case .peerUnknownOperation:
        return scheduled([.peerUnknownOperation(operationID: operationID)], for: action)
      case .sessionClosed:
        closed = true
        return [.closed(.protocolFailure)]
      case .pairRevoked:
        closed = true
        return [.closed(.pairRevoked)]
      case .sendFrame, .resultAcknowledgment:
        throw LocalError.missingFrame
      case .completed:
        throw LocalError.wrongPhase
      case .ignoredDuplicate, .noAction:
        return scheduled([], for: action)
      }
    }

    private func scheduled(
      _ commands: [Command],
      for action: RappBridgeAction
    ) -> [Command] {
      guard let deadline = action.nextPollAtMs else { return commands }
      return commands + [.scheduleLiveness(atMonotonicMilliseconds: deadline)]
    }

    private func operationCommand(
      _ action: RappBridgeAction,
      operationID: Data?,
      kind: OperationCommandKind
    ) throws -> Command {
      guard let operationID else { throw LocalError.missingOperationIdentifier }
      guard let descriptor = action.operation else { throw LocalError.missingOperation }
      let operation = Operation(descriptor)
      switch kind {
      case .inspect:
        return .inspectPrerequisites(operationID: operationID, operation: operation)
      case .approval:
        return .awaitUserApproval(operationID: operationID, operation: operation)
      case .safeRead:
        return .executeSafeRead(operationID: operationID, operation: operation)
      case .cardCommand:
        return .executeCardCommand(operationID: operationID, operation: operation)
      }
    }

    private func protocolFailure() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = try? bridge.closeSession()
      return [.closed(.protocolFailure)]
    }
  }
#endif
