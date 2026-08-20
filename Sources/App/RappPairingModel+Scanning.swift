// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
  import VisionKit
#endif

/// The holder's half of the ceremony: scanning an offer and pairing with
/// what it says.
extension RappPairingModel {
  #if os(iOS)
    internal func scanOffer() {
      resetAttempt()
      guard DataScannerViewController.isSupported,
        DataScannerViewController.isAvailable
      else {
        fail(String(localized: "The camera cannot scan pairing codes right now"))
        return
      }
      #if REFINEID_LOCAL_CARD
        PhonePersistentTokenRelay.shared.suspendForPairing()
      #endif
      phase = .scanning
    }

    internal func acceptScannedOffer(_ uri: String) {
      guard phase == .scanning else { return }
      beginPairing(uri)
    }

    #if DEBUG
      /// Pairs with an offer that arrived over the cable instead of the
      /// camera.
      ///
      /// A device driven from a Mac has no one to hold it up to a code.
      /// DEBUG only, and the offer is never echoed: it authorises a pairing
      /// for as long as it lives.
      internal func acceptOfferWithoutScanning(_ uri: String) {
        resetAttempt()
        #if REFINEID_LOCAL_CARD
          PhonePersistentTokenRelay.shared.suspendForPairing()
        #endif
        beginPairing(uri)
      }
    #endif

    private func beginPairing(_ uri: String) {
      phase = .connecting
      do {
        let candidates = try RappScannedOffer.candidates(scannedOfferURI: uri)
        if let applePeer = candidates.first(where: { candidate in
          candidate.profile == RappApplePeerProfile.name
        }) {
          try startApplePeerPairing(uri: uri, candidateID: applePeer.candidateID)
        } else if let stream = candidates.first(where: { candidate in
          candidate.profile == rappStreamProfileName()
        }) {
          try startApplePeerPairing(uri: uri, candidateID: stream.candidateID)
        } else {
          fail(String(localized: "The pairing code is invalid or expired"))
        }
      } catch {
        fail(String(localized: "The pairing code is invalid or expired"))
      }
    }

    private func startApplePeerPairing(uri: String, candidateID: String) throws {
      let relay = makeRelay(role: .cardHolder)
      let transport = makeTransport(relay: relay)
      let coordinator = try RappPairingCoordinator.proxy(
        scannedOfferURI: uri,
        selectedCandidateID: candidateID,
        displayName: UIDevice.current.name,
        platform: "iOS",
        vault: vault,
        transport: transport
      )
      install(coordinator: coordinator, relay: relay)
      relay.start(sharingOfferURI: uri)
    }
  #endif
}
