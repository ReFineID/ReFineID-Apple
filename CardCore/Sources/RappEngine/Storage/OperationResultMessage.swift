// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Profile-defined answer to one operation, as carried on the wire and
/// retained until the requester acknowledges it.
internal struct OperationResultMessage: Equatable {
  internal var operationIdentifier: Data
  internal var requestHash: Data
  internal var status: ResultStatus
  internal var error: ResultError?
  internal var result: CardOperationResult?

  internal func encoded() throws -> Data {
    var body: [String: WireValue] = [
      "operation_id": .bytes(operationIdentifier),
      "request_hash": .bytes(requestHash),
      "status": .text(status.rawValue),
      "body": .map(result.map(wireResultBody) ?? [:]),
    ]
    if let error {
      body["error"] = .text(error.rawValue)
    }
    do {
      return try WireValue.map(body).encoded()
    } catch {
      throw PairRecordError.invalidInput
    }
  }

  internal static func decode(_ bytes: Data) throws -> OperationResultMessage {
    var map = try decodedMap(bytes)
    let operationIdentifier = try takeBytes(&map, "operation_id")
    let requestHash = try takeBytes(&map, "request_hash")
    guard operationIdentifier.count == JournalSize.operationIdentifier,
      requestHash.count == JournalSize.requestHash
    else { throw PairRecordError.invalidInput }
    guard let status = ResultStatus(rawValue: try takeText(&map, "status")) else {
      throw PairRecordError.invalidInput
    }
    let error: ResultError?
    switch map.removeValue(forKey: "error") {
    case .none: error = nil
    case .some(.text(let name)):
      guard let parsed = ResultError(rawValue: name) else { throw PairRecordError.invalidInput }
      error = parsed
    case .some: throw PairRecordError.invalidInput
    }
    let resultBody = try takeMap(&map, "body")
    guard map.isEmpty else { throw PairRecordError.invalidInput }
    let result: CardOperationResult?
    if status == .completed {
      result = try wireResultFrom(resultBody)
    } else {
      guard resultBody.isEmpty else { throw PairRecordError.invalidInput }
      result = nil
    }
    let message = OperationResultMessage(
      operationIdentifier: operationIdentifier,
      requestHash: requestHash,
      status: status,
      error: error,
      result: result
    )
    guard message.isConsistent else { throw PairRecordError.invalidInput }
    return message
  }

  /// A completed result carries an output and no error; every other status
  /// carries a matching error and no output.
  private var isConsistent: Bool {
    switch (status, error, result) {
    case (.completed, .none, .some): true
    case (_, .some, .none): true
    default: false
    }
  }
}
