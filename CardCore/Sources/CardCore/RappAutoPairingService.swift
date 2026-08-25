// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Service managing automatic same-account device pairing and iCloud background synchronization.
  public final class RappAutoPairingService: @unchecked Sendable {
    // MARK: Static Properties

    /// The shared service instance.
    public static let shared = RappAutoPairingService()

    // MARK: Properties

    private var coordinator: RappCloudSyncCoordinator?
    private var externalChangeObserver: (any NSObjectProtocol)?
    private let lock = NSLock()
    private var isStarted = false

    // MARK: Initialization

    private init() {
      // Singleton instance initialization
    }

    // MARK: Public API

    /// Starts iCloud synchronization and listens for external device updates.
    public func start() {
      lock.lock()
      defer { lock.unlock() }

      guard !isStarted else { return }
      isStarted = true

      guard let identity = try? RappDeviceIdentity() else { return }
      let role: RappDeviceRole
      #if os(iOS)
        if SupportedCardTransports.offersNearField {
          role = .holder
        } else {
          role = .requester
        }
      #else
        role = .requester
      #endif

      let syncCoordinator = RappCloudSyncCoordinator(
        localIdentity: identity,
        localRole: role
      )
      self.coordinator = syncCoordinator

      // 1. Initial reconciliation
      Task { [weak self] in
        self?.reconcile()
      }

      // 2. Observe iCloud external changes
      externalChangeObserver = NotificationCenter.default.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: NSUbiquitousKeyValueStore.default,
        queue: .main
      ) { [weak self] _ in
        Task { [weak self] in
          self?.reconcile()
        }
      }
    }

    /// Triggers an immediate reconciliation of the cloud directory against the local device vault.
    public func reconcile() {
      guard let coordinator else { return }
      let vault = RappDeviceVault()
      Task {
        try? await coordinator.reconcileVault(vault: vault)
      }
    }

    deinit {
      if let observer = externalChangeObserver {
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }
#endif
