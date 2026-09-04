// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_REMOTE_CARD
  import CardCore
  import Foundation
  import RappEngine

  @MainActor
  extension PhonePersistentTokenRelay {
    /// Explicit UI action may call this after the user has corrected local
    /// credentials or deliberately chosen to reconnect.
    ///
    /// It never restores a revoked pair; the vault remains authoritative.
    internal func resumeAfterUserAction() {
      relistenPolicy = .automatic
      start()
    }

    /// Listens again while the policy still allows it, after a card that
    /// can be served has returned.
    internal func resumeServing() {
      guard relistenPolicy == .automatic else { return }
      start()
    }

    /// Stops advertising without asking the holder to pair again.
    ///
    /// The pairing remains. A card that comes back listens again.
    internal func stopServing() {
      tearDownTransport()
    }

    internal func stopListening() {
      relistenPolicy = .explicitUserActionRequired
      tearDownTransport()
    }

    /// Drops the listener and any open session, leaving the reconnect
    /// policy as the caller set it.
    private func tearDownTransport() {
      #if REFINEID_STREAM_TRANSPORT
        streamListener?.cancel()
        streamListener = nil
        streamContext = nil
      #else
        relay?.cancel()
        relay = nil
      #endif
      if let coord = coordinator {
        Task { await coord.transportClosed() }
        Task { await coord.close() }
      }
      coordinator = nil
      dispatcher = nil
      connectionID = nil
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      frameDelivery.reset()
      isActivelyConnected = false
    }

    internal func suspendForPairing() {
      relistenPolicy = .explicitUserActionRequired
      let closing = coordinator
      coordinator = nil
      relay?.cancel()
      relay = nil
      #if REFINEID_STREAM_TRANSPORT
        streamListener?.cancel()
        streamListener = nil
        streamContext = nil
      #endif
      connectionID = nil
      isActivelyConnected = false
      Task { await closing?.close() }
    }

    /// Tears down the closed connection and reconnects while automatic,
    /// yielding immediately for the nearby relay and pausing between
    /// stream dial attempts.
    internal func handleTransportClosed(redialDelayMilliseconds: Int) {
      let closingCoordinator = coordinator
      coordinator = nil
      dispatcher = nil
      relay = nil
      frameDelivery.reset()
      #if REFINEID_SLIM_RELAY
        slimSession = nil
        slimProxy = nil
      #endif
      #if REFINEID_STREAM_TRANSPORT
        streamListener = nil
        streamContext = nil
      #endif
      connectionID = nil
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      isActivelyConnected = false
      Task { await closingCoordinator?.transportClosed() }
      if !hasUsableSelectedPair() {
        relistenPolicy = .explicitUserActionRequired
      }
      guard relistenPolicy == .automatic else { return }
      Task { @MainActor in
        if redialDelayMilliseconds > 0 {
          try? await Task.sleep(for: .milliseconds(redialDelayMilliseconds))
        } else {
          await Task.yield()
        }
        self.start()
      }
    }
  }
#endif
