// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The answers already given, kept where the pairing is kept.
///
/// The journal record is the request's identifier, so a stored row names the
/// request it answered without a second encoding to keep in step with.
public struct SignRelayVaultJournal: SignRelayJournal {
  private let vault: RappDeviceVault
  private let pairID: Data

  /// Keeps this pairing's answers in `vault`.
  public init(vault: RappDeviceVault, pairID: Data) {
    self.vault = vault
    self.pairID = pairID
  }

  /// The request's identifier as the sixteen bytes the vault stores.
  private static func identifier(_ id: UUID) -> Data {
    withUnsafeBytes(of: id.uuid) { Data($0) }
  }

  /// The answer already given for `id`, if the vault kept one.
  ///
  /// - Parameter id: the request to look up.
  /// - Returns: the answer, or nil when this request has none.
  /// - Throws: when the vault cannot be read.
  public func answer(for id: UUID) throws -> PersistentRelayMessage? {
    let wanted = Self.identifier(id)
    for stored in try vault.loadProxy(pairID: pairID) where stored.record == wanted {
      guard let retained = stored.retainedResult else { return nil }
      return try PersistentRelayMessage.decoded(retained)
    }
    return nil
  }

  /// Records the answer given for `id`.
  ///
  /// - Parameters:
  ///   - answer: what the card produced.
  ///   - id: the request it answers.
  /// - Throws: when the vault cannot be written.
  public func record(_ answer: PersistentRelayMessage, for id: UUID) throws {
    try vault.persistProxyResult(
      pairID: pairID,
      operationID: Self.identifier(id),
      record: Self.identifier(id),
      result: try answer.encoded()
    )
  }
}
