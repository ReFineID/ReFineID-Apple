// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The pairing model's catalog and naming surface: what a settings screen
/// reads and the row actions it offers, apart from the ceremony itself.
extension RappPairingModel {
  /// Grants exactly the requested, supported profiles and proceeds to store
  /// the pairing.
  internal func confirmPeer(_ peer: RappPairingCoordinator.Peer) {
    guard let coordinator else { return }
    let grantSet = requestedProfiles(for: peer).filter(
      RappApplePeerProfile.isSupported)
    guard !grantSet.isEmpty else {
      denyPeer()
      return
    }
    phase = .connecting
    Task { await coordinator.approve(grantedProfiles: grantSet) }
  }

  internal func denyPeer() {
    guard let coordinator else {
      cancel()
      return
    }
    phase = .failed(String(localized: "Pairing was denied"))
    Task { [weak self] in
      await coordinator.deny()
      self?.finishAttempt()
      self?.resumeRegularRelay()
    }
  }

  internal func requestedProfiles(
    for peer: RappPairingCoordinator.Peer
  ) -> [String] {
    peer.requestedProfiles ?? RappApplePeerProfile.supportedCredentialProfiles
  }

  internal func profileLabel(_ profile: String) -> String {
    RappApplePeerProfile.label(for: profile)
  }

  internal func profileIsSupported(_ profile: String) -> Bool {
    RappApplePeerProfile.isSupported(profile)
  }

  internal func select(_ pair: RappPairingCoordinator.PairSummary) {
    Task {
      do {
        try await catalog.select(pairID: pair.pairID)
        selectedPairID = pair.pairID
        resumeRegularRelay()
      } catch {
        fail(String(localized: "The paired device is no longer available"))
      }
    }
  }

  internal func revoke(_ pair: RappPairingCoordinator.PairSummary) {
    Task {
      do {
        try await catalog.revoke(pairID: pair.pairID)
        RappPairNames.forget(pairID: pair.pairID)
        refresh()
      } catch {
        fail(String(localized: "The paired device could not be removed"))
      }
    }
  }

  /// The paired device's reviewed name, or its role when the pair
  /// predates remembered names.
  internal func displayName(
    for pair: RappPairingCoordinator.PairSummary
  ) -> String {
    RappPairNames.name(forPairID: pair.pairID) ?? pair.remotePlatformLabel
  }
}
