// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// This type's shape is the interface callers already wrote against. The begin
// methods name one parameter per field the operation carries, and the class is
// long because the operation protocol has that many steps; splitting it would
// put the state every step reads behind a wider access level for no gain.
// swiftlint:disable function_parameter_count type_body_length

/// The operation protocol running over one established session.
///
/// Every call answers with the bounded step the caller performs next. The
/// bridge decides what must happen; the caller performs it, so nothing here
/// touches a card, a transport, or a screen.
public final class RappOperationBridge: @unchecked Sendable {
  /// Which side of the pairing this bridge serves.
  internal enum Side {
    case proxy(ProxyOperationEngine)
    case requester(RequesterOperationEngine)
  }

  internal let lock = NSLock()
  internal let vault: RappOperationVault
  internal let pairIdentifier: Data
  internal let maximumLifetimeMilliseconds: UInt64
  internal var liveness: LivenessTracker
  internal var session: EstablishedSession
  internal var side: Side
  internal var closed = false

  private init(
    vault: RappOperationVault,
    pairIdentifier: Data,
    session: EstablishedSession,
    side: Side,
    maximumLifetimeMs: UInt64,
    liveness: RappLivenessConfiguration,
    nowMilliseconds: UInt64
  ) throws {
    self.vault = vault
    self.pairIdentifier = pairIdentifier
    self.session = session
    self.side = side
    self.maximumLifetimeMilliseconds = maximumLifetimeMs
    do {
      self.liveness = try LivenessTracker(
        configuration: LivenessConfiguration(
          baseIntervalMilliseconds: liveness.baseIntervalMs,
          responseTimeoutMilliseconds: liveness.responseTimeoutMs,
          maximumIntervalMilliseconds: liveness.maximumIntervalMs,
          maximumJitterMilliseconds: liveness.maximumJitterMs,
          maximumMisses: liveness.maximumMisses),
        nowMilliseconds: nowMilliseconds)
    } catch {
      throw RappBindingError.InvalidInput
    }
  }

  /// Runs the requester side over an established session.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when the session is not
  ///   established, and ``RappBindingError/LocalStateFailure`` when stored
  ///   records could not be recovered.
  public static func beginRequester(
    session: RappSessionBridge,
    vault: RappOperationVault,
    maximumLifetimeMs: UInt64,
    liveness: RappLivenessConfiguration,
    nowMs: UInt64
  ) throws -> RappOperationBridge {
    let established = try session.takeEstablished()
    let recovered = try recoveredRequesterRecords(
      vault: vault, pairIdentifier: established.pair.pairIdentifier)
    return try RappOperationBridge(
      vault: vault,
      pairIdentifier: established.pair.pairIdentifier,
      session: established.session,
      side: .requester(RequesterOperationEngine(recovered: recovered)),
      maximumLifetimeMs: maximumLifetimeMs,
      liveness: liveness,
      nowMilliseconds: nowMs)
  }

  /// Runs the proxy side over an established session.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when the session is not
  ///   established, and ``RappBindingError/LocalStateFailure`` when stored
  ///   records could not be recovered.
  public static func beginProxy(
    session: RappSessionBridge,
    vault: RappOperationVault,
    maximumLifetimeMs: UInt64,
    liveness: RappLivenessConfiguration,
    nowMs: UInt64
  ) throws -> RappOperationBridge {
    let established = try session.takeEstablished()
    let recovered = try recoveredProxyRecords(
      vault: vault, pairIdentifier: established.pair.pairIdentifier)
    return try RappOperationBridge(
      vault: vault,
      pairIdentifier: established.pair.pairIdentifier,
      session: established.session,
      side: .proxy(
        ProxyOperationEngine(
          grantedProfiles: established.pair.profiles, recovered: recovered)),
      maximumLifetimeMs: maximumLifetimeMs,
      liveness: liveness,
      nowMilliseconds: nowMs)
  }

  /// Names an engine failure in the public vocabulary.
  internal static func bindingError(_ error: EngineError) -> RappBindingError {
    switch error {
    case .authenticatedProtocolViolation:
      .ProtocolFailure
    case .unknownLocalOperation, .duplicateLocalOperationIdentifier, .invalidLocalValue:
      .InvalidInput
    default:
      .WrongPhase
    }
  }

  /// The proxy records stored for this pairing.
  private static func recoveredProxyRecords(
    vault: RappOperationVault, pairIdentifier: Data
  ) throws -> [RecoveredProxyRecord] {
    let stored: [RappStoredProxyJournal]
    do {
      stored = try vault.loadProxy(pairId: pairIdentifier)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
    return try stored.map { entry in
      do {
        return RecoveredProxyRecord(
          record: try ProxyJournalRecord.decode(entry.record),
          retainedResult: try entry.retainedResult.map(OperationResultMessage.decode))
      } catch {
        throw RappBindingError.LocalStateFailure
      }
    }
  }

  /// The requester records stored for this pairing.
  private static func recoveredRequesterRecords(
    vault: RappOperationVault, pairIdentifier: Data
  ) throws -> [RequesterJournalRecord] {
    let stored: [Data]
    do {
      stored = try vault.loadRequester(pairId: pairIdentifier)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
    return try stored.map { record in
      do {
        return try RequesterJournalRecord.decode(record)
      } catch {
        throw RappBindingError.LocalStateFailure
      }
    }
  }

  /// Begins a card and retry-state inspection.
  public func beginInspectCard(
    operationId: Data, localStartMs: UInt64, expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .inspectCard, operationId: operationId, localStartMs: localStartMs,
      expiresAfterMs: expiresAfterMs)
  }

  /// Begins a cardholder identity read.
  public func beginReadIdentity(
    operationId: Data, localStartMs: UInt64, expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .readIdentity, operationId: operationId, localStartMs: localStartMs,
      expiresAfterMs: expiresAfterMs)
  }

  /// Begins a certificate read, owned by the profile whose key it serves.
  public func beginReadCertificate(
    operationId: Data, signatureCertificate: Bool, localStartMs: UInt64, expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .readCertificate(kind: signatureCertificate ? .signature : .authentication),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Begins a browser authentication over an already-hashed challenge.
  public func beginBrowserAuthentication(
    operationId: Data,
    origin: String,
    keyProfile: RappCardKeyProfile,
    algorithm: RappSignatureAlgorithm,
    digest: Data,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .browserAuthenticate(
        origin: origin, keyProfile: keyProfile.engineProfile,
        algorithm: algorithm.engineAlgorithm, digest: digest),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Begins a document signature over a document digest.
  public func beginSignDocument(
    operationId: Data,
    documentName: String,
    keyProfile: RappCardKeyProfile,
    algorithm: RappSignatureAlgorithm,
    digest: Data,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .signDocument(
        documentName: documentName, keyProfile: keyProfile.engineProfile,
        algorithm: algorithm.engineAlgorithm, digest: digest),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Consumes one sealed frame from the peer.
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the frame does not
  ///   open or the authenticated peer sent something the protocol forbids.
  public func receiveFrame(bytes: Data, nowMs: UInt64) throws -> RappBridgeAction {
    try locked {
      let envelope: Envelope
      do {
        envelope = try session.open(bytes)
      } catch SessionError.integrityFailure {
        return closingAction(.sessionClosed)
      } catch {
        return closingAction(.pairRevoked)
      }
      if let livenessAction = try livenessReply(to: envelope, nowMs: nowMs) {
        return livenessAction
      }
      let message: TypedMessage
      do {
        message = try SessionMessageCodec.message(
          from: envelope,
          pairIdentifier: pairIdentifier,
          sessionIdentifier: session.sessionIdentifier,
          nowMilliseconds: nowMs)
      } catch {
        return closingAction(.pairRevoked)
      }
      return try dispatch(message, nowMs: nowMs)
    }
  }

  /// Probes the peer, or reports that the deadline has passed.
  public func pollLiveness(
    nowMs: UInt64, challenge: Data, jitterMs: Int64
  ) throws -> RappBridgeAction {
    try locked {
      guard let ping = PingChallenge(challenge) else { throw RappBindingError.InvalidInput }
      switch liveness.poll(
        nowMilliseconds: nowMs, nextChallenge: ping, jitterMilliseconds: jitterMs)
      {
      case .sendPing(let outstanding):
        let frame = try sealed(.livenessPing, body: ["challenge": .bytes(outstanding.bytes)])
        return RappBridgeAction(kind: .sendFrame, frame: frame)
      case .probeMissed(let nextProbeAtMilliseconds):
        return RappBridgeAction(kind: .noAction, nextPollAtMs: nextProbeAtMilliseconds)
      case .noAction:
        return RappBridgeAction(kind: .noAction)
      case .closeSession, .alreadyClosed:
        return closingAction(.sessionClosed)
      }
    }
  }

  /// Closes the session and classifies every operation still in flight.
  public func closeSession() throws -> RappBridgeAction {
    try locked {
      guard !closed else { return RappBridgeAction(kind: .noAction) }
      switch side {
      case .proxy(var engine):
        var store = VaultProxyJournalStore(vault: vault, pairIdentifier: pairIdentifier)
        _ = try? engine.sessionClosed(store: &store)
        side = .proxy(engine)
      case .requester(var engine):
        var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
        _ = try? engine.sessionClosed(store: &store)
        side = .requester(engine)
      }
      return closingAction(.sessionClosed)
    }
  }

  /// Starts one operation on the requester side and releases its request.
  internal func beginOperation(
    _ operation: CardOperation,
    operationId: Data,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try locked {
      guard case .requester(var engine) = side else { throw RappBindingError.WrongPhase }
      defer { side = .requester(engine) }
      var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      let message = try mapping { () -> TypedMessage in
        let request = try OperationRequest(
          operationIdentifier: operationId,
          pairIdentifier: pairIdentifier,
          sessionIdentifier: session.sessionIdentifier,
          profile: operation.requiredProfile,
          localStartMilliseconds: localStartMs,
          expiresAfterMilliseconds: expiresAfterMs,
          operation: operation)
        return try engine.begin(request, store: &store)
      }
      let frame = try sealedMessage(message)
      return RappBridgeAction(kind: .sendFrame, operationId: operationId, frame: frame)
    }
  }

  /// Runs one proxy step that produces a dispatch, writing the engine back.
  internal func withProxy(
    _ body: (inout ProxyOperationEngine, inout VaultProxyJournalStore) throws -> ProxyDispatch
  ) throws -> RappBridgeAction {
    try locked {
      guard case .proxy(var engine) = side else { throw RappBindingError.WrongPhase }
      defer { side = .proxy(engine) }
      var store = VaultProxyJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      let dispatch = try mapping { try body(&engine, &store) }
      return try action(for: dispatch)
    }
  }

  /// Records a stable failure and releases it.
  internal func finishFailure(operationId: Data, error: ResultError) throws -> RappBridgeAction {
    try withProxy { engine, store in
      try engine.finishFailure(operationIdentifier: operationId, error: error, store: &store)
    }
  }

  /// Retains a completed answer before it may be released.
  internal func complete(
    operationId: Data, result: CardOperationResult
  ) throws -> RappBridgeAction {
    try withProxy { engine, store in
      guard let reference = engine.reference(operationId) else {
        throw RappBindingError.WrongPhase
      }
      return try engine.finishCompleted(
        operationIdentifier: operationId,
        result: OperationResultMessage.completed(reference: reference, result: result),
        store: &store)
    }
  }

}

// swiftlint:enable function_parameter_count type_body_length
