// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Whether this phone can still serve a card, and what leaves with it.
  ///
  /// A connected reader or a stored NFC prime is a card this device can
  /// answer for. Losing both wipes the CryptoTokenKit identities that
  /// were offering that card, and stops the holder advertisement so a
  /// paired requester withdraws its copy. Pairing itself stays.
  ///
  /// An NFC field ending is not this event: the prime remains, and so
  /// does the advertisement.
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
      if !didMeasure, !canServe {
        didMeasure = true
        wasAbleToServe = false
        return
      }
      didMeasure = true
      guard wasAbleToServe != canServe else { return }
      wasAbleToServe = canServe
      if canServe {
        #if REFINEID_REMOTE_CARD
          PhonePersistentTokenRelay.shared.resumeServing()
        #endif
        return
      }
      ReaderPin1Cache.shared.clear()
      wipeLocalTokens()
      #if REFINEID_REMOTE_CARD
        PhonePersistentTokenRelay.shared.stopServing()
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
