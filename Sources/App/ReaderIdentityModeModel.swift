// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import CryptoTokenKit
  import SwiftUI

  /// Observes successfully minted reader identities without probing a card.
  @MainActor
  @Observable
  internal final class ReaderIdentityModeModel {
    /// Whether the platform is presenting a contact reader slot at all.
    ///
    /// A reader identity cannot exist without a reader. Asking the slot
    /// manager is a physical fact, where the token arithmetic below is
    /// an inference -- and an inference with a window in it: `ctkd`
    /// publishes a freshly minted NFC token before `registerSmartCard`
    /// has put it in the persistent list, so for a second after every
    /// setup that token looks exactly like a reader token. That window
    /// is what flashed a USB-C reader screen at a holder who had no
    /// reader attached.
    ///
    /// The built-in NFC slot exists only while a session is open and
    /// carries "NFC" in its name; a reader slot carries the reader's.
    private static var hasReaderSlot: Bool {
      guard let manager = TKSmartCardSlotManager.default else { return false }
      return manager.slotNames.contains { name in
        CardTransport.transport(forSlotNamed: name) == .reader
      }
    }

    /// Watches physical token publication and removal.
    private let watcher = TKTokenWatcher()

    /// One-shot removal handlers already installed for token IDs.
    private var removalHandlers: Set<String> = []

    /// The live reader tokens by identifier, including ones minted
    /// before this build, in a stable order.
    ///
    /// Named rather than counted: each identifier is one this model has
    /// already proved live and reader-backed, which is what makes it
    /// safe to ask the keychain about. A broad token search is active
    /// on iOS - it was measured opening a "Ready to Scan" sheet - and
    /// what wakes the field is a registered token that has to be minted
    /// to answer at all. A token already live answers from what it
    /// published.
    internal private(set) var liveReaderTokenIdentifiers: [String] = []

    /// Number of live reader tokens.
    internal var liveReaderTokenCount: Int {
      liveReaderTokenIdentifiers.count
    }

    /// Whether an inserted reader card published the authoritative empty
    /// token that means its factory credentials still require activation.
    internal var hasActivationRequiredCard: Bool {
      liveReaderTokenIdentifiers.contains(
        where: ActivationTokenIdentity.recognizes(tokenID:)
      )
    }

    /// Whether the setup form must be replaced by reader identity controls.
    internal var isActive: Bool {
      !liveReaderTokenIdentifiers.isEmpty
    }

    internal init() {
      watcher.setInsertionHandler(Self.insertionHandler(for: self))
    }

    /// Builds a ctkd callback with no inherited main-actor isolation.
    ///
    /// `TKTokenWatcher` invokes this block on its XPC queue. Constructing the
    /// block directly inside this main-actor type makes Swift trap before its
    /// body can enqueue the intended actor hop.
    nonisolated private static func insertionHandler(
      for model: ReaderIdentityModeModel
    ) -> @Sendable (String) -> Void {
      { [weak model] tokenIdentifier in
        guard CardTokenNamespace.owns(tokenIdentifier: tokenIdentifier) else {
          return
        }
        Task { @MainActor [weak model] in
          model?.refresh()
        }
      }
    }

    /// Builds a ctkd removal callback without main-actor isolation.
    nonisolated private static func removalHandler(
      for model: ReaderIdentityModeModel
    ) -> @Sendable (String) -> Void {
      { [weak model] removedTokenIdentifier in
        Task { @MainActor [weak model] in
          model?.tokenWasRemoved(removedTokenIdentifier)
        }
      }
    }

    /// Lists live reader tokens while excluding persistent NFC registrations.
    internal func refresh() {
      guard Self.hasReaderSlot else {
        liveReaderTokenIdentifiers = []
        return
      }
      let refineIDTokenIdentifiers = Set(
        watcher.tokenIDs.filter(CardTokenNamespace.owns(tokenIdentifier:))
      )
      let registeredTokenIdentifiers = Set(
        TKSmartCardTokenRegistrationManager.default.registeredSmartCardTokens
          .filter(CardTokenNamespace.owns(tokenIdentifier:))
      )
      // Persistent registrations are ReFineID's NFC identities. A token that
      // is live in the watcher but absent from that list is backed by a
      // connected reader. This remains true across an app upgrade even when
      // ctkd keeps the old extension instance and token objects alive.
      //
      // Sorted, so the rows a holder reads keep one order across a
      // refresh that changed nothing.
      liveReaderTokenIdentifiers =
        refineIDTokenIdentifiers.subtracting(registeredTokenIdentifiers).sorted()

      for tokenIdentifier in liveReaderTokenIdentifiers {
        observeRemoval(of: tokenIdentifier)
      }
    }

    /// Refreshes the UI when one physical token leaves.
    private func observeRemoval(of tokenIdentifier: String) {
      guard removalHandlers.insert(tokenIdentifier).inserted else { return }
      watcher.addRemovalHandler(
        Self.removalHandler(for: self),
        forTokenID: tokenIdentifier
      )
    }

    /// Applies one removal only after the callback has reached the main actor.
    private func tokenWasRemoved(_ tokenIdentifier: String) {
      removalHandlers.remove(tokenIdentifier)
      refresh()
    }
  }

#endif
