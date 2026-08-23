// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Whether this phone can still serve a card, and what leaves with it.
  ///
  /// A connected reader is a card this device can answer for. Losing it
  /// wipes the CryptoTokenKit identities that were offering that card,
  /// revokes every pairing, and stops the holder advertisement so a
  /// paired requester withdraws its copy and pairing too.
  ///
  /// A stored NFC prime is different: the field has no lasting connected
  /// state, so the prime, the advertisement, and the pairing stay.
  @MainActor
  internal enum HolderCardServing {
    /// Whether a serving state has been measured this run.
    private static var didMeasure = false

    /// Last computed serving state, so an unchanged recount is silent.
    private static var wasAbleToServe = false

    /// Recomputes from the reader slot and the prime store.
    internal static func availabilityChanged() {
      guard SupportedCardTransports.offersNearField else { return }
      guard !DemoMode.shared.isActive else { return }
      let canServe =
        PrimeStore.storedCount() > 0 || CardPresence.shared.isReaderCardPresent
      if !didMeasure {
        guard CardPresence.shared.hasCompletedInitialScan else { return }
        didMeasure = true
        wasAbleToServe = canServe
        if canServe {
          #if REFINEID_REMOTE_CARD
            PhonePersistentTokenRelay.shared.resumeServing()
          #endif
        } else {
          dropCardAndPairing()
        }
        return
      }
      guard wasAbleToServe != canServe else { return }
      wasAbleToServe = canServe
      if canServe {
        #if REFINEID_REMOTE_CARD
          PhonePersistentTokenRelay.shared.resumeServing()
        #endif
        return
      }
      dropCardAndPairing()
    }

    /// Clears identities and pairings that belonged to a reader card.
    private static func dropCardAndPairing() {
      ReaderPin1Cache.shared.clear()
      wipeLocalTokens()
      #if REFINEID_REMOTE_CARD
        Task {
          await PhonePersistentTokenRelay.shared.revokeBecauseCardUnavailable()
          RappPairingModel.revokeEveryStoredPair()
        }
      #endif
    }

    /// Removes ReFineID's published smart-card identities.
    ///
    /// Live reader tokens are already gone with the slot; this clears the
    /// registrations and driver configurations that would otherwise keep
    /// offering a card that is no longer here.
    private static func wipeLocalTokens() {
      Task.detached(priority: .utility) {
        #if os(iOS)
          let manager = TKSmartCardTokenRegistrationManager.default
          let tokenIDs = manager.registeredSmartCardTokens
            .filter(CardTokenNamespace.owns(tokenIdentifier:))
          for tokenID in tokenIDs {
            try? manager.unregisterSmartCard(tokenID: tokenID)
          }
        #endif
        _ = DriverConfiguredCredentials.dropIdentityTokenConfigurations()
      }
    }
  }

#endif
