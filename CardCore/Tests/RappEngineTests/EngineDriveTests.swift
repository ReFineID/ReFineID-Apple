// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Both engines answer each other over an in-memory channel

import Foundation
import Testing

@testable import RappEngine

private func engineRequest(
  operation: CardOperation,
  operationIdentifier: Data = EngineFixture.operationIdentifier
) throws -> OperationRequest {
  try OperationRequest(
    operationIdentifier: operationIdentifier,
    pairIdentifier: EngineFixture.pairIdentifier,
    sessionIdentifier: EngineFixture.sessionIdentifier,
    profile: operation.requiredProfile,
    localStartMilliseconds: EngineFixture.startMilliseconds,
    expiresAfterMilliseconds: EngineFixture.expiresAfterMilliseconds,
    operation: operation)
}

private func signingOperation() -> CardOperation {
  .browserAuthenticate(
    origin: EngineFixture.origin,
    keyProfile: .rsa3072,
    algorithm: .rsaPkcs1Sha256,
    digest: EngineFixture.digest)
}

/// Drives one consequential operation from request to acknowledgement.
///
/// Returns the two engines and the store so a caller can inspect what durable
/// state the exchange produced.
private func driveHappyPath() throws -> HappyPath {
  var store = MemoryJournalStore()
  var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
  var requester = RequesterOperationEngine(recovered: [])
  let request = try engineRequest(operation: signingOperation())
  let identifier = request.operationIdentifier

  let requestMessage = try requester.begin(request, store: &store)
  let inspect = try proxy.receive(
    requestMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
    maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  EngineReport.check(
    inspect == .inspectPrerequisites(operationIdentifier: identifier),
    "a granted request reaches prerequisite inspection")

  try proxy.prerequisitesComplete(operationIdentifier: identifier)
  let approval = try UserApproval(
    for: request, approvedAtMilliseconds: EngineFixture.nowMilliseconds)
  let prepared = try proxy.approve(
    operationIdentifier: identifier, approval: approval,
    nowMilliseconds: EngineFixture.nowMilliseconds,
    maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  guard case .send(let preparedMessage) = prepared else {
    EngineReport.check(false, "approval prepares a consequential action")
    return HappyPath(proxy: proxy, requester: requester, store: store)
  }

  let preparedDispatch = try requester.receive(preparedMessage, store: &store)
  EngineReport.check(
    preparedDispatch == .prepared(operationIdentifier: identifier),
    "the requester accepts the prepared echo")

  let commitMessage = try requester.commit(operationIdentifier: identifier, store: &store)
  let beginCommand = try proxy.receive(
    commitMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
    maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  EngineReport.check(
    beginCommand == .beginCardCommand(operationIdentifier: identifier),
    "a valid commit authorizes the one card command")

  let pending = try proxy.beginCardCommand(operationIdentifier: identifier, store: &store)
  let transmitted = pending.execute { command in command.operation }
  EngineReport.check(
    transmitted == signingOperation(), "the command handed out is the approved operation")
  EngineReport.check(
    store.transmissionsRecorded == 1, "exactly one transmission reached storage")

  let reference = try OperationReference(of: request)
  let result = OperationResultMessage.completed(
    reference: reference, result: .signature(EngineFixture.signature))
  let sendResult = try proxy.finishCompleted(
    operationIdentifier: identifier, result: result, store: &store)
  guard case .send(let resultMessage) = sendResult else {
    EngineReport.check(false, "a completed result is retained then released")
    return HappyPath(proxy: proxy, requester: requester, store: store)
  }

  let resultDispatch = try requester.receive(resultMessage, store: &store)
  guard case .sendResultAcknowledgement(_, let ackMessage) = resultDispatch else {
    EngineReport.check(false, "a completed result asks for an acknowledgement")
    return HappyPath(proxy: proxy, requester: requester, store: store)
  }

  let acknowledged = try proxy.receive(
    ackMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
    maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  EngineReport.check(
    acknowledged == .resultAcknowledged(operationIdentifier: identifier),
    "the proxy records the acknowledgement")

  let released = try requester.acknowledgementReleased(
    operationIdentifier: identifier, store: &store)
  EngineReport.check(
    released == .signature(EngineFixture.signature),
    "the requester releases the signature to its caller")
  EngineReport.check(
    proxy.liveOperationStates[identifier] == .completed
      && requester.liveOperationStates[identifier] == .completed,
    "both engines end the operation completed")
  return HappyPath(proxy: proxy, requester: requester, store: store)
}

// The scenario runs as one continuous drive, because that is what it proves:
// each step depends on the state the previous one left, and a peer answers a
// real predecessor rather than a fixture. Splitting it into separate tests
// would thread that state through setup and stop testing the sequence.
@Suite("RAPP proxy and requester engines")
internal struct EngineDriveTests {
  @Test("Both engines answer each other over an in-memory channel")
  internal func run() throws {
    let happy = try driveHappyPath()
    do {
      var store = MemoryJournalStore()
      var proxy = ProxyOperationEngine(
        grantedProfiles: [.authentication, .cardStatus], recovered: [])
      let first = try engineRequest(operation: signingOperation())
      _ = try proxy.receive(
        .operationRequest(first), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      let statesBefore = proxy.liveOperationStates
      let second = try engineRequest(
        operation: .inspectCard, operationIdentifier: EngineFixture.secondOperationIdentifier)
      let refusal = try proxy.receive(
        .operationRequest(second), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      EngineReport.check(refusal == .send(.error(.busy)), "a second request is refused as busy")
      EngineReport.check(
        proxy.liveOperationStates == statesBefore, "the refusal changed no operation state")
      EngineReport.check(
        ProtocolErrorMessage.busy.name == "busy", "the refusal uses the registered error name")
    }
    do {
      var store = MemoryJournalStore()
      var proxy = ProxyOperationEngine(grantedProfiles: [.cardStatus], recovered: [])
      let request = try engineRequest(operation: signingOperation())
      var refused = false
      do {
        _ = try proxy.receive(
          .operationRequest(request), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
          maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      } catch EngineError.authenticatedProtocolViolation(.profileNotGranted) {
        refused = true
      }
      EngineReport.check(refused, "an ungranted profile is an authenticated violation")
      EngineReport.check(
        proxy.liveOperationStates.isEmpty, "no operation was created for the refused request")
      EngineReport.check(
        store.proxyWrites.isEmpty, "nothing was journaled, so no card contact was possible")
    }
    do {
      var store = MemoryJournalStore()
      var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
      var requester = RequesterOperationEngine(recovered: [])
      let request = try engineRequest(operation: signingOperation())
      let identifier = request.operationIdentifier
      let requestMessage = try requester.begin(request, store: &store)
      _ = try proxy.receive(
        requestMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      try proxy.prerequisitesComplete(operationIdentifier: identifier)

      let denial = try proxy.finishFailure(
        operationIdentifier: identifier, error: .userDenied, store: &store)
      guard case .sendFailure(let deniedMessage, let closesOnDenial) = denial else {
        EngineReport.check(false, "a denial produces a failure result")
        return
      }
      EngineReport.check(!closesOnDenial, "a denial does not close the session")
      let deniedDispatch = try requester.receive(deniedMessage, store: &store)
      EngineReport.check(
        deniedDispatch == .terminal(operationIdentifier: identifier, state: .denied),
        "the requester journals the denial as terminal")

      var model = RappState(role: .proxy)
      model.pairing = .pairedConnected
      model.session = .healthy
      model.operation = .executing
      let outcome = model.credentialRejected()
      EngineReport.check(
        model.operation == .credentialRejected,
        "the tables end a credential-rejected operation")
      EngineReport.check(
        model.session != .healthy, "the tables close the session on a rejected credential")
      EngineReport.check(
        model.requiresUserIntent, "a rejected credential requires fresh user intent")
      EngineReport.check(!outcome.actions.isEmpty, "the credential rejection emits actions")

      var ambiguous = RappState(role: .requester)
      ambiguous.pairing = .pairedConnected
      ambiguous.session = .healthy
      ambiguous.operation = .committed
      _ = ambiguous.sessionIntegrityFailed()
      EngineReport.check(
        ambiguous.operation == .ambiguous,
        "a session lost after commit leaves the operation ambiguous")
      EngineReport.check(
        ambiguous.pairing == .pairedConnected,
        "an unattributable loss keeps the pairing, per INV-18")
    }
    do {
      var store = MemoryJournalStore()
      var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
      let request = try engineRequest(operation: signingOperation())
      let identifier = request.operationIdentifier
      _ = try proxy.receive(
        .operationRequest(request), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      try proxy.prerequisitesComplete(operationIdentifier: identifier)
      let approval = try UserApproval(
        for: request, approvedAtMilliseconds: EngineFixture.nowMilliseconds)
      _ = try proxy.approve(
        operationIdentifier: identifier, approval: approval,
        nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      let reference = try OperationReference(of: request)
      _ = try proxy.receive(
        .operationCommit(reference), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      let pending = try proxy.beginCardCommand(operationIdentifier: identifier, store: &store)
      _ = pending.execute { _ in true }

      let repeated = try proxy.receive(
        .operationCommit(reference), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      EngineReport.check(
        repeated == .ignoredDuplicateCommit(operationIdentifier: identifier),
        "a repeated commit is discarded, not re-executed")

      var secondCommand = false
      do {
        _ = try proxy.beginCardCommand(operationIdentifier: identifier, store: &store)
        secondCommand = true
      } catch {
        secondCommand = false
      }
      EngineReport.check(!secondCommand, "a second card command is refused after the first")
      EngineReport.check(
        store.transmissionsRecorded == 1, "storage still records exactly one transmission")

      var reused = false
      do {
        _ = try proxy.receive(
          .operationRequest(request), store: &store,
          nowMilliseconds: EngineFixture.nowMilliseconds,
          maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      } catch EngineError.authenticatedProtocolViolation(.activeOperationIdentifierReused) {
        reused = true
      }
      EngineReport.check(reused, "replaying the request for a live operation is a violation")
      EngineReport.check(
        store.transmissionsRecorded == 1, "the replay transmitted nothing further")
    }
    do {
      var store = MemoryJournalStore()
      var requester = RequesterOperationEngine(recovered: [])
      let request = try engineRequest(operation: signingOperation())
      _ = try requester.begin(request, store: &store)
      let reference = try OperationReference(of: request)
      // An identity body cannot answer a signing request.
      let wrong = OperationResultMessage.completed(
        reference: reference,
        result: .identity(
          displayName: EngineFixture.displayName, personIdentifier: EngineFixture.personIdentifier))
      var refused = false
      do {
        _ = try requester.receive(.operationResult(wrong), store: &store)
      } catch EngineError.authenticatedProtocolViolation(.invalidOperationMessage) {
        refused = true
      }
      EngineReport.check(refused, "a result that answers another operation is a violation")

      let foreign = OperationReference(
        operationIdentifier: EngineFixture.secondOperationIdentifier,
        requestHash: reference.requestHash)
      let unknown = try requester.receive(
        .operationResult(
          OperationResultMessage.completed(
            reference: foreign, result: .signature(EngineFixture.signature))),
        store: &store)
      EngineReport.check(
        unknown
          == .ignoredStale(
            operationIdentifier: EngineFixture.secondOperationIdentifier,
            response: .error(
              .unknownOperation(operationIdentifier: EngineFixture.secondOperationIdentifier))),
        "a result for an unknown operation is a stale-reference race")
    }
    do {
      var store = MemoryJournalStore()
      var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
      let request = try engineRequest(operation: signingOperation())
      let identifier = request.operationIdentifier
      _ = try proxy.receive(
        .operationRequest(request), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      let before = proxy.liveOperationStates[identifier]
      let liveness = try proxy.receive(
        .other(.livenessPing), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      EngineReport.check(
        liveness == .notOperation(.other(.livenessPing)),
        "liveness is not an operation message")
      EngineReport.check(
        proxy.liveOperationStates[identifier] == before,
        "liveness left the in-flight operation untouched")

      var model = RappState(role: .proxy)
      model.pairing = .pairedConnected
      model.session = .healthy
      model.operation = .prepared
      _ = model.livenessMissed()
      EngineReport.check(
        !model.operationAdmissionPermitted, "a missed probe blocks new operation admission")
      EngineReport.check(
        model.operation == .prepared, "a missed probe does not disturb the live operation")
      _ = model.livenessRestored()
      EngineReport.check(model.session == .healthy, "an exact echo restores the session")
    }
    do {
      var store = MemoryJournalStore()
      var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
      let request = try engineRequest(operation: signingOperation())
      let identifier = request.operationIdentifier
      _ = try proxy.receive(
        .operationRequest(request), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      try proxy.prerequisitesComplete(operationIdentifier: identifier)
      let approval = try UserApproval(
        for: request, approvedAtMilliseconds: EngineFixture.nowMilliseconds)
      _ = try proxy.approve(
        operationIdentifier: identifier, approval: approval,
        nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      let reference = try OperationReference(of: request)
      let expired = try proxy.receive(
        .operationCommit(reference), store: &store,
        nowMilliseconds: EngineFixture.expiredNowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      guard case .send(.operationResult(let expiredResult)) = expired else {
        EngineReport.check(false, "a late commit answers with an expired result")
        return
      }
      EngineReport.check(
        expiredResult.error == .requestExpired, "a late commit is expired, not a violation")
      EngineReport.check(
        store.transmissionsRecorded == 0, "an expired commit transmitted nothing")
    }

    do {
      var store = MemoryJournalStore()
      var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
      let request = try engineRequest(operation: signingOperation())
      let identifier = request.operationIdentifier
      _ = try proxy.receive(
        .operationRequest(request), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      try proxy.prerequisitesComplete(operationIdentifier: identifier)
      let approval = try UserApproval(
        for: request, approvedAtMilliseconds: EngineFixture.nowMilliseconds)
      _ = try proxy.approve(
        operationIdentifier: identifier, approval: approval,
        nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      let reference = try OperationReference(of: request)
      _ = try proxy.receive(
        .operationCommit(reference), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      store.failNextWrite = true
      var handedOut = true
      do {
        _ = try proxy.beginCardCommand(operationIdentifier: identifier, store: &store)
      } catch {
        handedOut = false
      }
      EngineReport.check(!handedOut, "a failed write hands out no card command")
      EngineReport.check(
        store.transmissionsRecorded == 0,
        "no transmission is recorded when the write failed")
    }
    do {
      // The four bodies the engines must be able to SEND, encoded through
      // TypedMessage rather than assembled by hand in a test.
      let corpus = try CorpusFile.operation(filePath: #filePath)
      var pinned: [String: String] = [:]
      for entry in corpus.vectors {
        pinned[entry.name] = entry.bodyHex
      }
      let statusIdentifier = Data(repeating: 0x44, count: 16)
      let errorIdentifier = Data(repeating: 0x66, count: 16)
      let statusHash = Data(repeating: 0x55, count: 32)
      // Cancel echoes the ordinary operation reference, not the status one.
      let cancelReference = OperationReference(
        operationIdentifier: Data(repeating: 0x22, count: 16),
        requestHash: Data(repeating: 0x33, count: 32))

      func encodedHex(_ message: TypedMessage) throws -> String {
        guard let bytes = try message.encodedBody() else { return "" }
        return bytes.map { String(format: "%02x", $0) }.joined()
      }

      let cases: [(String, TypedMessage)] = [
        (
          "cancel-with-reason",
          .operationCancel(
            CancelMessage(reference: cancelReference, reason: EngineFixture.cancelReason))
        ),
        (
          "cancel-without-reason",
          .operationCancel(CancelMessage(reference: cancelReference, reason: nil))
        ),
        ("status-request", .operationStatusRequest(operationIdentifier: statusIdentifier)),
        (
          "status-known-completed",
          .operationStatus(
            StatusReport(
              operationIdentifier: statusIdentifier, known: true, state: .completed,
              requestHash: statusHash))
        ),
        (
          "status-unknown",
          .operationStatus(StatusReport(operationIdentifier: statusIdentifier, known: false))
        ),
        ("error-busy", .error(.busy)),
        (
          "error-unknown-operation-with-id",
          .error(.unknownOperation(operationIdentifier: errorIdentifier))
        ),
        ("error-unknown-operation-bare", .error(.unknownOperation(operationIdentifier: nil))),
      ]
      for (name, message) in cases {
        let produced = try encodedHex(message)
        EngineReport.check(
          !produced.isEmpty && produced == pinned[name], "\(name) encodes to the pinned bytes")
      }
      // The trap: the wire form omits absent fields, so an unknown status is a
      // two-key map, never the journal's four-key form with explicit nulls.
      let unknownBody = StatusReport(operationIdentifier: statusIdentifier, known: false).wireBody
      EngineReport.check(
        unknownBody.count == 2, "an unknown status omits state and request_hash")
    }
    do {
      // Proving the at-most-once check is real: counting every journal write as a
      // transmission would let the happy path look like two.
      let writesInHappyPath = happy.store.proxyWrites.count
      EngineReport.check(
        writesInHappyPath > 1 && happy.store.transmissionsRecorded == 1,
        "several journal writes occurred but exactly one was a transmission")
    }
  }
}
