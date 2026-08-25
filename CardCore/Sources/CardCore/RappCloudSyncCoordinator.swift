// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Coordinates zero-touch device pairing across devices sharing the same Apple ID.
  ///
  /// Periodically or upon change notifications, this coordinator syncs device public keys
  /// through iCloud Key-Value storage and reconciles them into the local `RappDeviceVault`.
  public actor RappCloudSyncCoordinator {
    // MARK: Constants

    /// The key in `NSUbiquitousKeyValueStore` holding all registered device records.
    public static let cloudDevicesKey = "fi.refineid.rapp.cloud_devices"

    // MARK: Properties

    /// The persistent cryptographic identity of the local device.
    public let localIdentity: RappDeviceIdentity
    /// The operational role of the local device.
    public let localRole: RappDeviceRole
    private let cloudStorage: any RappCloudStorage
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: Initialization

    /// Creates a coordinator for synchronizing same-account devices.
    public init(
      localIdentity: RappDeviceIdentity,
      localRole: RappDeviceRole,
      cloudStorage: any RappCloudStorage = UbiquitousKeyValueStoreCloudStorage()
    ) {
      self.localIdentity = localIdentity
      self.localRole = localRole
      self.cloudStorage = cloudStorage
      self.encoder = JSONEncoder()
      self.encoder.dateEncodingStrategy = .iso8601
      self.decoder = JSONDecoder()
      self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Public API

    /// Publishes this device's current public record into the iCloud directory.
    @discardableResult
    public func publishLocalDevice() -> RappCloudDeviceRecord {
      var directory = loadDirectory()
      let record = RappCloudDeviceRecord(
        deviceID: localIdentity.deviceID,
        deviceName: localIdentity.deviceName,
        modelName: localIdentity.modelName,
        role: localRole,
        staticPublicKey: localIdentity.publicKeyData,
        rendezvousToken: RappSameAccountPairBuilder.deriveRendezvousToken(
          publicKeyA: localIdentity.publicKeyData,
          publicKeyB: localIdentity.publicKeyData
        ),
        updatedAt: Date()
      )
      directory[localIdentity.deviceID] = record
      saveDirectory(directory)
      return record
    }

    /// Removes this device from the iCloud directory (e.g. on sign out or app reset).
    public func unpublishLocalDevice() {
      var directory = loadDirectory()
      directory.removeValue(forKey: localIdentity.deviceID)
      saveDirectory(directory)
    }

    /// Fetches all remote devices currently registered in iCloud.
    public func remoteDevices() -> [RappCloudDeviceRecord] {
      let directory = loadDirectory()
      return directory.values
        .filter { $0.deviceID != localIdentity.deviceID }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Reconciles the cloud directory against the local device vault.
    ///
    /// Any compatible peer (e.g. an iPhone holder when we are a Mac/iPad requester)
    /// is automatically instantiated as a `RappPairRecord` and stored in `RappDeviceVault`.
    ///
    /// - Returns: The list of established/active same-account pairs.
    @discardableResult
    public func reconcileVault(vault: RappDeviceVault) throws -> [RappPairRecord] {
      // 1. Ensure local device is published
      publishLocalDevice()

      let remotes = remoteDevices()
      var establishedPairs: [RappPairRecord] = []

      for remote in remotes {
        // Pair with peers of the complementary role (or all peers if applicable)
        let isComplementary =
          (localRole == .requester && remote.role == .holder)
          || (localRole == .holder && remote.role == .requester)

        guard isComplementary else { continue }

        let pairID = RappSameAccountPairBuilder.derivePairIdentifier(
          publicKeyA: localIdentity.publicKeyData,
          publicKeyB: remote.staticPublicKey
        )

        // If pair is revoked locally, do not resurrect it
        if try vault.pairIsRevoked(pairID: pairID) {
          continue
        }

        let existingRecordData = try vault.loadPair(pairID: pairID)
        let pair: RappPairRecord
        if let existingRecordData {
          pair = try RappPairRecord.decode(from: existingRecordData)
        } else {
          let endpointRole: RappEndpointRole = (localRole == .requester) ? .requester : .proxy
          pair = try RappSameAccountPairBuilder.makePairRecord(
            localStaticPrivate: localIdentity.privateKeyData,
            localStaticPublic: localIdentity.publicKeyData,
            localRole: endpointRole,
            remotePublicKey: remote.staticPublicKey
          )
          try pair.persistDeviceOnly(vault: vault)
        }

        establishedPairs.append(pair)

        // If local is a requester and has no current selection, auto-select this holder
        if localRole == .requester, try vault.selectedPairID() == nil {
          try vault.selectPair(pairID: pairID)
        }
      }

      return establishedPairs
    }

    // MARK: Private Helpers

    private func loadDirectory() -> [UUID: RappCloudDeviceRecord] {
      guard let data = cloudStorage.data(forKey: Self.cloudDevicesKey) else {
        return [:]
      }
      return (try? decoder.decode([UUID: RappCloudDeviceRecord].self, from: data)) ?? [:]
    }

    private func saveDirectory(_ directory: [UUID: RappCloudDeviceRecord]) {
      guard let data = try? encoder.encode(directory) else { return }
      cloudStorage.set(data, forKey: Self.cloudDevicesKey)
      _ = cloudStorage.synchronize()
    }
  }
#endif
