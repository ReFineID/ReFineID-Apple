// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// What the model does with each event the pairing ceremony reports.
extension RappPairingModel {
  internal func receive(
    _ event: RappPairingCoordinator.Event,
    from coordinator: RappPairingCoordinator
  ) {
    guard self.coordinator === coordinator else { return }
    switch event {
    case .offerReady(let uri):
      phase = .offer(uri)
    case .offerRestored(let uri):
      restoreRequesterOffer(uri, coordinator: coordinator)
    case .reviewPeer(let peer):
      reviewedPeerName = peer.displayName
      // The scan of the offer QR, carrying its 256-bit bearer secret, is the
      // human consent that authorizes this pairing and its public reads. Only
      // a device that saw the code can reach this point, on either side, so
      // both confirm without asking again.
      confirmPeer(peer)
    case .paired(let pair):
      do {
        try vault.selectPair(pairID: pair.pairID)
        if let reviewedPeerName {
          RappPairNames.remember(reviewedPeerName, pairID: pair.pairID)
        }
        selectedPairID = pair.pairID
        phase = .paired(pair)
        refresh()
        finishAttempt()
        resumeRegularRelay()
      } catch {
        fail(String(localized: "The paired device could not be selected"))
      }
    case .closed(let reason):
      guard !isFinished else { return }
      #if DEBUG
        print("[pairing] closed \(String(describing: reason))")
      #endif
      fail(String(localized: "Pairing ended before it was completed"))
    }
  }

  internal func restoreRequesterOffer(
    _ uri: String,
    coordinator: RappPairingCoordinator
  ) {
    phase = .offer(uri)
    relay?.cancel()
    let replacement = makeRelay(role: .host)
    let replacementTransport = makeTransport(relay: replacement)
    relay = replacement
    Task { @MainActor [weak self] in
      guard await coordinator.replaceTransport(replacementTransport),
        let self,
        self.coordinator === coordinator,
        !isFinished
      else {
        self?.fail(String(localized: "Pairing could not be started"))
        return
      }
      replacement.start(sharingOfferURI: uri)
    }
  }
}
