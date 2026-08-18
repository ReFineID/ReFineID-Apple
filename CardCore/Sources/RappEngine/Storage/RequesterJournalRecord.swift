// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Storage-format versions of the two operation journals.
internal let requesterJournalFormatVersion: UInt64 = 1

/// Requester's durable record of one operation.
internal struct RequesterJournalRecord: Equatable {
  internal var pairIdentifier: Data
  internal var sessionIdentifier: Data
  internal var operationIdentifier: Data
  internal var requestHash: Data
  internal var state: OperationState
  internal var retainedResult: CardOperationResult?
  internal var reconciliation: StatusReport?

  internal func encoded() throws -> Data {
    let value = WireValue.map([
      "format_version": .unsigned(requesterJournalFormatVersion),
      "pair_id": .bytes(pairIdentifier),
      "session_id": .bytes(sessionIdentifier),
      "operation_id": .bytes(operationIdentifier),
      "request_hash": .bytes(requestHash),
      "state": .text(state.rawValue),
      "retained_result": retainedResult.map(journalResultValue) ?? .null,
      "reconciliation": reconciliation.map(statusReportValue) ?? .null,
    ])
    do {
      return try value.encoded()
    } catch {
      throw PairRecordError.invalidInput
    }
  }

  internal static func decode(_ bytes: Data) throws -> RequesterJournalRecord {
    var map = try decodedMap(bytes)
    guard try takeUnsigned(&map, "format_version") == requesterJournalFormatVersion else {
      throw PairRecordError.invalidInput
    }
    let pairIdentifier = try takeBytes(&map, "pair_id")
    let sessionIdentifier = try takeBytes(&map, "session_id")
    let operationIdentifier = try takeBytes(&map, "operation_id")
    let requestHash = try takeBytes(&map, "request_hash")
    guard pairIdentifier.count == PairRecordSize.pairIdentifier,
      sessionIdentifier.count == JournalSize.sessionIdentifier,
      operationIdentifier.count == JournalSize.operationIdentifier,
      requestHash.count == JournalSize.requestHash
    else { throw PairRecordError.invalidInput }
    guard let state = OperationState(rawValue: try takeText(&map, "state")) else {
      throw PairRecordError.invalidInput
    }
    let retainedResult: CardOperationResult?
    switch try takeStoredValue(&map, "retained_result") {
    case .null: retainedResult = nil
    case let value: retainedResult = try journalResultFrom(value)
    }
    let reconciliation: StatusReport?
    switch try takeStoredValue(&map, "reconciliation") {
    case .null: reconciliation = nil
    case let value: reconciliation = try statusReportFrom(value)
    }
    guard map.isEmpty else { throw PairRecordError.invalidInput }
    return RequesterJournalRecord(
      pairIdentifier: pairIdentifier,
      sessionIdentifier: sessionIdentifier,
      operationIdentifier: operationIdentifier,
      requestHash: requestHash,
      state: state,
      retainedResult: retainedResult,
      reconciliation: reconciliation
    )
  }
}
