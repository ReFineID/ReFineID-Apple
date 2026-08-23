// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import RappEngine
  import SwiftUI

  /// The holder's half of the ceremony: entering an 8-character pairing code
  /// and pairing with what it describes.
  extension RappPairingModel {
    private static let defaultOfferLifetimeMilliseconds: UInt64 = 180_000

    internal func startCodeEntry() {
      resetAttempt()
      #if REFINEID_LOCAL_CARD && os(iOS)
        PhonePersistentTokenRelay.shared.suspendForPairing()
      #endif
      phase = .codeEntry
    }

    internal func acceptPairingCode(_ rawCode: String) {
      let code = RappPairingCode.normalize(rawCode)
      guard RappPairingCode.isValid(code) else {
        fail(String(localized: "The pairing code is invalid or expired"))
        return
      }
      do {
        let (_, uri) = try RappPairingCode.pairingOffer(
          for: code,
          profiles: RappApplePeerProfile.supportedCredentialProfiles,
          candidate: Self.offeredCandidate.binding,
          lifetimeMilliseconds: Self.defaultOfferLifetimeMilliseconds
        )
        beginPairing(uri)
      } catch {
        fail(String(localized: "The pairing code is invalid or expired"))
      }
    }

    #if DEBUG
      /// Pairs with an offer URI directly.
      internal func acceptOfferWithoutScanning(_ uri: String) {
        resetAttempt()
        #if REFINEID_LOCAL_CARD && os(iOS)
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
      #if os(macOS)
        let displayName = Host.current().localizedName ?? "Mac"
        let platform = "macOS"
      #else
        let displayName = UIDevice.current.name
        let platform = "iOS"
      #endif
      let coordinator = try RappPairingCoordinator.proxy(
        scannedOfferURI: uri,
        selectedCandidateID: candidateID,
        displayName: displayName,
        platform: platform,
        vault: vault,
        transport: transport
      )
      install(coordinator: coordinator, relay: relay)
      relay.start(sharingOfferURI: uri)
    }
  }
#endif
