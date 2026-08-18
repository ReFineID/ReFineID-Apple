// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// The dispatch tables are long because the protocol has that many outcomes;
// each arm is one line of mapping.
// swiftlint:disable cyclomatic_complexity

/// Turning an engine dispatch into the caller's next step.
extension RappOperationBridge {
  /// Classifies one authenticated message on whichever side runs here.
  internal func dispatch(_ message: TypedMessage, nowMs: UInt64) throws -> RappBridgeAction {
    // The engine is a value, so its new state is stored before the action is
    // built. Building an action reads the engine to describe the operation the
    // message just created, and a deferred store would leave that read looking
    // at the state from before the message arrived.
    switch side {
    case .proxy(var engine):
      var store = VaultProxyJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      let dispatch: ProxyDispatch
      do {
        dispatch = try mapping {
          try engine.receive(
            message, store: &store, nowMilliseconds: nowMs,
            maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
        }
      } catch {
        side = .proxy(engine)
        throw error
      }
      side = .proxy(engine)
      return try action(for: dispatch)
    case .requester(var engine):
      var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      let dispatch: RequesterDispatch
      do {
        dispatch = try mapping { try engine.receive(message, store: &store) }
      } catch {
        side = .requester(engine)
        throw error
      }
      side = .requester(engine)
      return try action(for: dispatch)
    }
  }

  /// Answers a liveness ping, or records a pong, before the operation layer
  /// sees the envelope.
  internal func livenessReply(to envelope: Envelope, nowMs: UInt64) throws -> RappBridgeAction? {
    switch envelope.messageType {
    case .livenessPing:
      var body = envelope.body
      let challenge = try takeBytes(&body, "challenge")
      let frame = try sealed(.livenessPong, body: ["challenge": .bytes(challenge)])
      return RappBridgeAction(kind: .sendFrame, frame: frame)
    case .livenessPong:
      var body = envelope.body
      let echo = try takeBytes(&body, "challenge")
      guard let challenge = PingChallenge(echo) else { return RappBridgeAction(kind: .noAction) }
      _ = liveness.receivePong(nowMilliseconds: nowMs, challenge: challenge)
      return RappBridgeAction(kind: .noAction)
    case .sessionClose:
      return closingAction(.sessionClosed)
    default:
      return nil
    }
  }

  /// The caller's next step for one proxy dispatch.
  internal func action(for dispatch: ProxyDispatch) throws -> RappBridgeAction {
    switch dispatch {
    case .send(let message):
      return RappBridgeAction(
        kind: .sendFrame,
        operationId: message.referencedOperationIdentifier,
        frame: try sealedMessage(message))
    case .sendFailure(let message, let closeSession):
      return RappBridgeAction(
        kind: .sendFrame,
        operationId: message.referencedOperationIdentifier,
        frame: try sealedMessage(message),
        closeSessionAfterSend: closeSession)
    case .inspectPrerequisites(let operationIdentifier):
      return try operationAction(.inspectPrerequisites, operationIdentifier: operationIdentifier)
    case .executeSafeRead(let operationIdentifier, _):
      return try operationAction(.executeSafeRead, operationIdentifier: operationIdentifier)
    case .beginCardCommand(let operationIdentifier):
      return try operationAction(.executeCardCommand, operationIdentifier: operationIdentifier)
    case .advisoryCancellation(let operationIdentifier):
      return RappBridgeAction(kind: .advisoryCancellation, operationId: operationIdentifier)
    case .cancelled(let operationIdentifier):
      return RappBridgeAction(
        kind: .cancelled, operationId: operationIdentifier,
        terminalState: OperationState.cancelled.rawValue,
        terminalReason: .cancelled)
    case .resultAcknowledged(let operationIdentifier):
      return RappBridgeAction(kind: .resultAcknowledged, operationId: operationIdentifier)
    case .ignoredDuplicateCommit(let operationIdentifier):
      return RappBridgeAction(kind: .ignoredDuplicate, operationId: operationIdentifier)
    case .ignoredStale(let operationIdentifier, let response):
      return RappBridgeAction(
        kind: .sendFrame, operationId: operationIdentifier,
        frame: try sealedMessage(response))
    case .notOperation:
      return RappBridgeAction(kind: .noAction)
    }
  }

  /// The caller's next step for one requester dispatch.
  internal func action(for dispatch: RequesterDispatch) throws -> RappBridgeAction {
    switch dispatch {
    case .prepared(let operationIdentifier):
      guard case .requester(var engine) = side else { throw RappBindingError.WrongPhase }
      defer { side = .requester(engine) }
      var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      let message = try mapping {
        try engine.commit(operationIdentifier: operationIdentifier, store: &store)
      }
      return RappBridgeAction(
        kind: .sendFrame, operationId: operationIdentifier,
        frame: try sealedMessage(message))
    case .sendResultAcknowledgement(let operationIdentifier, let message):
      return RappBridgeAction(
        kind: .resultAcknowledgment, operationId: operationIdentifier,
        frame: try sealedMessage(message))
    case .terminal(let operationIdentifier, let state):
      return RappBridgeAction(
        kind: .terminal, operationId: operationIdentifier, terminalState: state.rawValue)
    case .cancellationReceived(let operationIdentifier, let state):
      return RappBridgeAction(
        kind: .cancelled, operationId: operationIdentifier, terminalState: state.rawValue,
        terminalReason: .cancelled)
    case .peerBusy:
      return RappBridgeAction(kind: .peerBusy)
    case .peerUnknownOperation(let operationIdentifier):
      return RappBridgeAction(kind: .peerUnknownOperation, operationId: operationIdentifier)
    case .statusAnnotated(let operationIdentifier):
      return RappBridgeAction(kind: .noAction, operationId: operationIdentifier)
    case .ignoredStale(let operationIdentifier, let response):
      return RappBridgeAction(
        kind: .sendFrame, operationId: operationIdentifier,
        frame: try sealedMessage(response))
    case .notOperation:
      return RappBridgeAction(kind: .noAction)
    }
  }

  /// A step naming the operation the holder is being asked about.
  internal func operationAction(
    _ kind: RappBridgeActionKind, operationIdentifier: Data
  ) throws -> RappBridgeAction {
    guard case .proxy(let engine) = side, let operation = engine.operation(operationIdentifier)
    else { throw RappBindingError.WrongPhase }
    return RappBridgeAction(
      kind: kind,
      operationId: operationIdentifier,
      operation: RappOperationDescriptor(operation))
  }

  /// Marks the bridge spent and names why.
  internal func closingAction(_ kind: RappBridgeActionKind) -> RappBridgeAction {
    closed = true
    session.close()
    return RappBridgeAction(kind: kind)
  }

  internal func sealedMessage(_ message: TypedMessage) throws -> Data {
    try mapping { try SessionMessageCodec.frame(for: message, session: &session) }
  }

  internal func sealed(_ messageType: MessageType, body: [String: WireValue]) throws -> Data {
    try mapping { try session.seal(messageType, body: body) }
  }

  internal func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  /// Runs an engine step, naming its failure in the public vocabulary.
  internal func mapping<Value>(_ body: () throws -> Value) throws -> Value {
    do {
      return try body()
    } catch let error as RappBindingError {
      throw error
    } catch let error as EngineError {
      throw Self.bindingError(error)
    } catch is AuthorizationError, is CardOperationError, is JournalError {
      throw RappBindingError.WrongPhase
    } catch is SessionError {
      throw RappBindingError.ProtocolFailure
    } catch {
      throw RappBindingError.LocalStateFailure
    }
  }
}

// swiftlint:enable cyclomatic_complexity
