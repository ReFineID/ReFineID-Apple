// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappBridgeActionKind {
    /// Whether the step names an operation for the card or the holder.
    internal var isOperationStep: Bool {
      switch self {
      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
        .executeCardCommand, .terminal, .cancelled, .advisoryCancellation:
        true
      default:
        false
      }
    }
  }

  /// Turning one bridge action into the caller's commands.
  extension RappOperationDriver {
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
          return [.closed(revokedWhileClosing ? .pairRevoked : .terminalFrameReleased)]
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
      _ = bridge.closeSession()
      return [.closed(.transportClosed)]
    }

    /// Closes the session at local request.
    public func close() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = bridge.closeSession()
      return [.closed(.localRequest)]
    }

    internal func commands(_ action: RappBridgeAction) throws -> [Command] {
      if action.revokesPairing {
        // Revocation is durable before any notice frame is released, so
        // the pairing is dead even if the notice never arrives. A failed
        // write still closes and fail-stops this connection; the vault
        // stays authoritative for the next start.
        revokedWhileClosing = true
        try? vault.revokeDeviceOnly(pairId: pairID, revokedAtMs: clock.wallMilliseconds())
      }
      if let frame = action.frame {
        return try scheduled([.send(frame: frame, release: release(for: action))], for: action)
      }
      if action.kind.isOperationStep {
        return try stepCommands(action)
      }
      return try lifecycleCommands(action)
    }

    /// The release token the transport must return for one frame.
    private func release(for action: RappBridgeAction) throws -> FrameRelease {
      if action.kind == .resultAcknowledgment {
        guard let operationID = action.operationId else {
          throw LocalError.missingOperationIdentifier
        }
        return .resultAcknowledgment(operationID: operationID)
      }
      return action.closeSessionAfterSend ? .closeSession : .none
    }

    /// Commands for the steps that name an operation.
    private func stepCommands(_ action: RappBridgeAction) throws -> [Command] {
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
      default:
        throw LocalError.wrongPhase
      }
    }

    /// Commands for the session-level outcomes.
    private func lifecycleCommands(_ action: RappBridgeAction) throws -> [Command] {
      let operationID = action.operationId
      switch action.kind {
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
      default:
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

    internal func protocolFailure() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = bridge.closeSession()
      return [.closed(.protocolFailure)]
    }
  }
#endif
