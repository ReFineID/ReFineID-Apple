// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  extension PersistentTokenRegistry {
    /// Seconds a vanished advertisement may stay missing before the
    /// borrowed identity is withdrawn.
    ///
    /// Bonjour browse results drop a live name for a moment without
    /// the holder having left.
    private static let advertisementLossHoldSeconds = 30

    private static var advertisementLossHold: Duration {
      Duration.seconds(advertisementLossHoldSeconds)
    }

    /// The published name both sides derive from the selected pairing.
    private static func holderServiceName() -> String? {
      guard let pairID = activePairID else { return nil }
      let vault = RappDeviceVault()
      guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
      else { return nil }
      return StreamRendezvousName.name(sharing: pair.metadata().rendezvousToken)
    }

    /// Browses for the selected pair's holder advertisement.
    ///
    /// The holder publishes only while it can serve a card. Losing that
    /// service means the reader card is gone: the borrowed identity is
    /// withdrawn. The pairing stays so the next card can use it. An NFC
    /// prime keeps the holder advertising.
    internal func startWatchingPresence() {
      guard presence == nil else { return }
      advertisementLossTask?.cancel()
      advertisementLossTask = nil
      hasSeenHolderAdvertisement = false
      holderIsAdvertising = false
      guard let name = Self.holderServiceName(), !name.isEmpty else {
        Self.withdrawPublishedIdentity()
        return
      }
      let watcher = StreamRelayPresence(matching: name) { present in
        Task { @MainActor in
          Self.shared.holderPresenceChanged(present)
        }
      }
      presence = watcher
      watcher.start()
    }

    /// Restarts browsing for the currently selected holder.
    internal func restartWatchingPresence() {
      presence?.cancel()
      presence = nil
      advertisementLossTask?.cancel()
      advertisementLossTask = nil
      hasSeenHolderAdvertisement = false
      holderIsAdvertising = false
      startWatchingPresence()
    }

    internal func holderPresenceChanged(_ present: Bool) {
      guard let name = Self.holderServiceName(), !name.isEmpty else {
        advertisementLossTask?.cancel()
        advertisementLossTask = nil
        hasSeenHolderAdvertisement = false
        holderIsAdvertising = false
        Self.withdrawPublishedIdentity()
        return
      }
      if present {
        advertisementLossTask?.cancel()
        advertisementLossTask = nil
        hasSeenHolderAdvertisement = true
        holderIsAdvertising = true
        if Self.needsIdentity || certificateDER == nil {
          startFetch(replacing: true)
        } else {
          seedHolderLine()
        }
        return
      }
      guard hasSeenHolderAdvertisement, holderIsAdvertising else { return }
      advertisementLossTask?.cancel()
      advertisementLossTask = Task { @MainActor in
        try? await Task.sleep(for: Self.advertisementLossHold)
        guard !Task.isCancelled else { return }
        holderIsAdvertising = false
        Self.withdrawPublishedIdentity()
        #if DEBUG
          print("[persistent-token] holder left, withdrew identity")
          fflush(stdout)
        #endif
      }
    }

    internal func installPairingObservers() {
      guard pairingsObservers.isEmpty else { return }
      let notificationCenter = NotificationCenter.default
      let observer1 = notificationCenter.addObserver(
        forName: RappPairingModel.pairingsDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.restartWatchingPresence()
        }
      }
      let observer2 = notificationCenter.addObserver(
        forName: RappAutoPairingService.pairingsDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.restartWatchingPresence()
        }
      }
      pairingsObservers = [observer1, observer2]
    }
  }
#endif
