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
        #if REFINEID_STREAM_TRANSPORT
        if streamListener == nil, coordinator == nil { start() }
        #else
        if relay == nil, coordinator == nil { start() }
        #endif
    }

    internal func stopListening() {
        relistenPolicy = .explicitUserActionRequired
        #if REFINEID_STREAM_TRANSPORT
        streamListener?.cancel()
        streamListener = nil
        streamContext = nil
        #else
        relay?.cancel()
        relay = nil
        #endif
        if let coord = coordinator {
            // Notify the remote side that the transport is closed intentionally.
            Task { await coord.transportClosed() }
            Task { await coord.close() }
        }
        coordinator = nil
        dispatcher = nil
        connectionID = nil
        preCoordinatorFrames.removeAll(keepingCapacity: false)
        frameDelivery.reset()
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
