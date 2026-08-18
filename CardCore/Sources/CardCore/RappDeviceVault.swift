// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Device-bound storage for RAPP pair keys and durable operation journals.
///
/// Every public mutation maps to one Keychain add or update. Pair revocation
/// atomically erases key material and replaces it with a tombstone. Proxy
/// records and retained results share one item so result transitions remain
/// atomic without decoding Rust-owned journal bytes.
public final class RappDeviceVault: @unchecked Sendable {

  // MARK: Nested Types

  /// Storage failures surfaced by vault operations.
  public enum Failure: Error, Equatable, Sendable {
    case duplicate
    case malformed
    case notFound
    case unavailable(OSStatus)
  }

  /// One proxy operation journal and its optionally retained result.
  public struct StoredProxyJournal: Equatable, Sendable {

    // MARK: Properties

    /// Rust-owned journal bytes for the proxy operation.
    public let record: Data
    /// Result bytes retained for redelivery; absent once acknowledged.
    public let retainedResult: Data?

    // MARK: Lifecycle

    /// Creates a snapshot pairing journal bytes with a retained result.
    public init(record: Data, retainedResult: Data?) {
      self.record = record
      self.retainedResult = retainedResult
    }

  }

  private enum PairState: String, Codable {
    case active
    case revoked
  }

  private struct PairMarker: Codable {
    let state: PairState
    let revokedAtMilliseconds: UInt64?
  }

  private struct Namespace {

    // MARK: Properties

    let pair: String
    let requester: String
    let proxy: String
    let selection: String

    // MARK: Lifecycle

    init(prefix: String) {
      pair = "\(prefix).pair"
      requester = "\(prefix).requester"
      proxy = "\(prefix).proxy"
      selection = "\(prefix).selection"
    }

  }

  private enum SelectionAccount {
    static let current = "current"
  }

  private enum IdentifierSize {
    static let pair = 16
    static let operation = 16
  }

  private enum StoredValue {
    /// Keychain does not reliably replace a non-empty generic-password value
    /// with zero-length data.
    ///
    /// This non-CBOR marker gives acknowledged proxy records one durable,
    /// portable representation without deleting their Rust-owned journal
    /// bytes.
    static let noRetainedResult = Data("ReFineID:RAPP:no-retained-result:v1".utf8)
  }

  private enum RetainedResultMutation {
    case preserve
    case replace(Data?)
  }

  // MARK: Properties

  private let accessGroup: String?
  private let namespace: Namespace
  private let lock = NSLock()
  private let encoder: PropertyListEncoder
  private let decoder = PropertyListDecoder()

  // MARK: Lifecycle

  /// Opens the production vault, optionally shared via an access group.
  public convenience init(accessGroup: String? = nil) {
    self.init(accessGroup: accessGroup, servicePrefix: "fi.refineid.rapp")
  }

  /// Isolates deterministic integration tests from production and from each
  /// simulated peer.
  ///
  /// Production always enters through the public initializer.
  internal init(accessGroup: String?, servicePrefix: String) {
    precondition(!servicePrefix.isEmpty)
    self.accessGroup = accessGroup
    namespace = Namespace(prefix: servicePrefix)
    encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
  }

  // MARK: Functions

  /// Stores a new active pair record under its pair identifier.
  public func insertPair(pairID: Data, record: Data) throws {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      guard !record.isEmpty else { throw Failure.malformed }
      let marker = try pairMarker(state: .active, revokedAtMilliseconds: nil)
      var item = itemQuery(service: namespace.pair, account: pairID.hexadecimal)
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      item[kSecAttrGeneric as String] = marker
      item[kSecValueData as String] = record
      let status = SecItemAdd(item as CFDictionary, nil)
      switch status {
      case errSecSuccess:
        return
      case errSecDuplicateItem:
        throw Failure.duplicate
      default:
        throw Failure.unavailable(status)
      }
    }
  }

  /// Returns the pair record, or nil when it is absent or revoked.
  public func loadPair(pairID: Data) throws -> Data? {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      guard let item = try loadOne(service: namespace.pair, account: pairID.hexadecimal) else {
        return nil
      }
      let marker = try decodePairMarker(item)
      guard marker.state == .active else { return nil }
      guard let record = item[kSecValueData as String] as? Data, !record.isEmpty else {
        throw Failure.malformed
      }
      return record
    }
  }

  /// Reports whether a revocation tombstone exists for the pair.
  public func pairIsRevoked(pairID: Data) throws -> Bool {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      guard let item = try loadOne(service: namespace.pair, account: pairID.hexadecimal) else {
        return false
      }
      return try decodePairMarker(item).state == .revoked
    }
  }

  /// Lists the identifiers of stored pairs that are not revoked.
  public func activePairIDs() throws -> [Data] {
    try synchronized {
      try loadAll(service: namespace.pair).compactMap { item in
        let marker = try decodePairMarker(item)
        guard marker.state == .active else { return nil }
        guard
          let account = item[kSecAttrAccount as String] as? String,
          let pairID = Data(strictHexadecimal: account),
          pairID.count == IdentifierSize.pair
        else {
          throw Failure.malformed
        }
        return pairID
      }
    }
  }

  /// Returns the identifier of the currently selected pair, if any.
  public func selectedPairID() throws -> Data? {
    try synchronized {
      guard
        let item = try loadOne(
          service: namespace.selection,
          account: SelectionAccount.current
        )
      else { return nil }
      guard
        let pairID = item[kSecValueData as String] as? Data,
        pairID.count == IdentifierSize.pair
      else { throw Failure.malformed }
      return pairID
    }
  }

  /// Marks an active pair as the current selection.
  public func selectPair(pairID: Data) throws {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      guard
        let item = try loadOne(
          service: namespace.pair,
          account: pairID.hexadecimal
        ),
        try decodePairMarker(item).state == .active
      else { throw Failure.notFound }
      try upsert(
        service: namespace.selection,
        account: SelectionAccount.current,
        attributes: [kSecValueData as String: pairID]
      )
    }
  }

  /// Removes the current pair selection, if any.
  public func clearSelectedPair() throws {
    try synchronized {
      let status = SecItemDelete(
        itemQuery(
          service: namespace.selection,
          account: SelectionAccount.current
        ) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw Failure.unavailable(status)
      }
    }
  }

  /// Erases the pair's key material and installs a revocation tombstone.
  public func revokePair(pairID: Data, revokedAtMilliseconds: UInt64) throws {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      let marker = try pairMarker(
        state: .revoked,
        revokedAtMilliseconds: revokedAtMilliseconds)
      let attributes: [String: Any] = [
        kSecAttrGeneric as String: marker,
        kSecValueData as String: Data(),
      ]
      try updateExisting(
        service: namespace.pair,
        account: pairID.hexadecimal,
        attributes: attributes)
    }
  }

  /// Writes or replaces one requester journal record for the operation.
  public func persistRequester(
    pairID: Data,
    operationID: Data,
    record: Data
  ) throws {
    try synchronized {
      try requireOperationIdentifiers(pairID: pairID, operationID: operationID)
      guard !record.isEmpty else { throw Failure.malformed }
      try upsert(
        service: operationService(namespace: namespace.requester, pairID: pairID),
        account: operationID.hexadecimal,
        attributes: [kSecValueData as String: record])
    }
  }

  /// Returns all requester journal records stored for the pair.
  public func loadRequester(pairID: Data) throws -> [Data] {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      return try loadAll(
        service: operationService(namespace: namespace.requester, pairID: pairID)
      ).map { item in
        guard let record = item[kSecValueData as String] as? Data, !record.isEmpty else {
          throw Failure.malformed
        }
        return record
      }
    }
  }

  /// Writes the proxy journal record with no retained result.
  public func persistProxy(
    pairID: Data,
    operationID: Data,
    record: Data
  ) throws {
    try persistProxyValue(
      pairID: pairID,
      operationID: operationID,
      record: record,
      retainedResult: .replace(nil))
  }

  /// Writes the proxy journal record together with its retained result.
  public func persistProxyResult(
    pairID: Data,
    operationID: Data,
    record: Data,
    result: Data
  ) throws {
    guard !result.isEmpty else { throw Failure.malformed }
    try persistProxyValue(
      pairID: pairID,
      operationID: operationID,
      record: record,
      retainedResult: .replace(result))
  }

  /// Updates an existing proxy record, preserving its retained result.
  public func retainProxyUncertain(
    pairID: Data,
    operationID: Data,
    record: Data
  ) throws {
    try persistProxyValue(
      pairID: pairID,
      operationID: operationID,
      record: record,
      retainedResult: .preserve)
  }

  /// Replaces the proxy record and discards its retained result.
  public func acknowledgeProxyResult(
    pairID: Data,
    operationID: Data,
    record: Data
  ) throws {
    try persistProxyValue(
      pairID: pairID,
      operationID: operationID,
      record: record,
      retainedResult: .replace(nil))
  }

  /// Returns every stored proxy journal for the pair.
  public func loadProxy(pairID: Data) throws -> [StoredProxyJournal] {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      return try loadAll(
        service: operationService(namespace: namespace.proxy, pairID: pairID)
      ).map { item in
        guard let record = item[kSecAttrGeneric as String] as? Data, !record.isEmpty,
          let result = item[kSecValueData as String] as? Data
        else {
          throw Failure.malformed
        }
        return StoredProxyJournal(
          record: record,
          retainedResult: result.isEmpty || result == StoredValue.noRetainedResult
            ? nil
            : result)
      }
    }
  }

  /// Deletes all requester and proxy journal records for the pair.
  public func removeOperationRecords(pairID: Data) throws {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      try deleteAll(service: operationService(namespace: namespace.requester, pairID: pairID))
      try deleteAll(service: operationService(namespace: namespace.proxy, pairID: pairID))
    }
  }

  private func persistProxyValue(
    pairID: Data,
    operationID: Data,
    record: Data,
    retainedResult: RetainedResultMutation
  ) throws {
    try synchronized {
      try requireOperationIdentifiers(pairID: pairID, operationID: operationID)
      guard !record.isEmpty else { throw Failure.malformed }
      let service = operationService(namespace: namespace.proxy, pairID: pairID)
      let account = operationID.hexadecimal
      var attributes: [String: Any] = [kSecAttrGeneric as String: record]
      switch retainedResult {
      case .preserve:
        try updateExisting(service: service, account: account, attributes: attributes)
      case .replace(let result):
        attributes[kSecValueData as String] = result ?? StoredValue.noRetainedResult
        try upsert(service: service, account: account, attributes: attributes)
      }
    }
  }

  private func pairMarker(
    state: PairState,
    revokedAtMilliseconds: UInt64?
  ) throws -> Data {
    do {
      return try encoder.encode(
        PairMarker(state: state, revokedAtMilliseconds: revokedAtMilliseconds))
    } catch {
      throw Failure.malformed
    }
  }

  private func decodePairMarker(_ item: [String: Any]) throws -> PairMarker {
    guard let data = item[kSecAttrGeneric as String] as? Data else {
      throw Failure.malformed
    }
    do {
      return try decoder.decode(PairMarker.self, from: data)
    } catch {
      throw Failure.malformed
    }
  }

  private func operationService(namespace: String, pairID: Data) -> String {
    "\(namespace).\(pairID.hexadecimal)"
  }

  private func requireOperationIdentifiers(pairID: Data, operationID: Data) throws {
    try requireIdentifier(pairID, size: IdentifierSize.pair)
    try requireIdentifier(operationID, size: IdentifierSize.operation)
  }

  private func requireIdentifier(_ value: Data, size: Int) throws {
    guard value.count == size else { throw Failure.malformed }
  }

  private func itemQuery(service: String, account: String? = nil) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
    if let account {
      query[kSecAttrAccount as String] = account
    }
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  private func loadOne(service: String, account: String) throws -> [String: Any]? {
    var query = itemQuery(service: service, account: account)
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    switch status {
    case errSecSuccess:
      guard let item = output as? [String: Any] else { throw Failure.malformed }
      return item
    case errSecItemNotFound:
      return nil
    default:
      throw Failure.unavailable(status)
    }
  }

  private func loadAll(service: String) throws -> [[String: Any]] {
    var query = itemQuery(service: service)
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    switch status {
    case errSecSuccess:
      guard let attributes = output as? [[String: Any]] else { throw Failure.malformed }
      let items = try attributes.map { item in
        guard let account = item[kSecAttrAccount as String] as? String else {
          throw Failure.malformed
        }
        guard let loaded = try loadOne(service: service, account: account) else {
          throw Failure.notFound
        }
        return loaded
      }
      return items.sorted {
        ($0[kSecAttrAccount as String] as? String ?? "")
          < ($1[kSecAttrAccount as String] as? String ?? "")
      }
    case errSecItemNotFound:
      return []
    default:
      throw Failure.unavailable(status)
    }
  }

  private func updateExisting(
    service: String,
    account: String,
    attributes: [String: Any]
  ) throws {
    let status = SecItemUpdate(
      itemQuery(service: service, account: account) as CFDictionary,
      attributes as CFDictionary)
    switch status {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      throw Failure.notFound
    default:
      throw Failure.unavailable(status)
    }
  }

  private func upsert(
    service: String,
    account: String,
    attributes: [String: Any]
  ) throws {
    let query = itemQuery(service: service, account: account)
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw Failure.unavailable(updateStatus)
    }

    var item = query
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    for (key, value) in attributes {
      item[key] = value
    }
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    if addStatus == errSecSuccess { return }
    if addStatus == errSecDuplicateItem {
      let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      guard retryStatus == errSecSuccess else { throw Failure.unavailable(retryStatus) }
      return
    }
    throw Failure.unavailable(addStatus)
  }

  private func deleteAll(service: String) throws {
    let status = SecItemDelete(itemQuery(service: service) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure.unavailable(status)
    }
  }

  private func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}

extension Data {
  private enum Hexadecimal {
    static let digitsPerByte = 2
    static let radix: UInt = 16
  }

  fileprivate var hexadecimal: String {
    map { String(format: "%02x", $0) }.joined()
  }

  fileprivate init?(strictHexadecimal value: String) {
    guard value.count.isMultiple(of: Hexadecimal.digitsPerByte) else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(value.count / Hexadecimal.digitsPerByte)
    var index = value.startIndex
    while index < value.endIndex {
      let next = value.index(index, offsetBy: Hexadecimal.digitsPerByte)
      guard let byte = UInt8(value[index..<next], radix: Hexadecimal.radix) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}
