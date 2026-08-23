// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  extension PersistentTokenRegistry {
    /// The published name both sides derive from the selected pairing.
    private static func holderServiceName() -> String? {
      let vault = RappDeviceVault()
      guard let pairID = try? vault.selectedPairID(),
        let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
      else { return nil }
      return StreamRendezvousName.name(sharing: pair.metadata().rendezvousToken)
    }

    /// Browses for the selected pair's holder advertisement.
    ///
    /// The holder publishes only while it can serve a card. Losing that
    /// service means the reader card is gone: the borrowed identity and
    /// the pairing both leave. An NFC prime keeps the holder advertising.
    internal func startWatchingPresence() {
      presence?.cancel()
      presence = nil
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
        hasSeenHolderAdvertisement = true
        holderIsAdvertising = true
        if Self.needsIdentity {
          startFetch(replacing: false)
        }
        return
      }
      guard hasSeenHolderAdvertisement, holderIsAdvertising else { return }
      holderIsAdvertising = false
      Self.withdrawPublishedIdentity()
      RappPairingModel.revokeEveryStoredPair()
      presence?.cancel()
      presence = nil
      #if DEBUG
        print("[persistent-token] holder left, withdrew pairing")
        fflush(stdout)
      #endif
    }
  }
#endif
