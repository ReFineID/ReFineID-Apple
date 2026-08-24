// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  extension PersistentTokenRegistry {
    /// Seconds a vanished advertisement may stay missing before the
    /// borrowed identity is withdrawn.
    ///
    /// Bonjour browse results drop a live name for a moment without
    /// the holder having left.
    private static let advertisementLossHoldSeconds = 2

    private static var advertisementLossHold: Duration {
      Duration.seconds(advertisementLossHoldSeconds)
    }

    /// The published name both sides derive from the selected pairing.
    private static func holderServiceName() -> String? {
      let vault = RappDeviceVault()
      let pairID = (try? vault.selectedPairID()) ?? (try? vault.activePairIDs().first)
      guard let pairID,
        let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
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
      presence?.cancel()
      presence = nil
      advertisementLossTask?.cancel()
      advertisementLossTask = nil
      hasSeenHolderAdvertisement = false
      holderIsAdvertising = false
      guard let name = Self.holderServiceName() else { return }
      let watcher = StreamRelayPresence(matching: name) { present in
        Task { @MainActor in
          Self.shared.holderPresenceChanged(present)
        }
      }
      presence = watcher
      watcher.start()
    }

    internal func holderPresenceChanged(_ present: Bool) {
      if present {
        advertisementLossTask?.cancel()
        advertisementLossTask = nil
        hasSeenHolderAdvertisement = true
        holderIsAdvertising = true
        if Self.needsIdentity {
          startFetch(replacing: false)
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
  }
#endif
