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

    /// Number of live reader tokens, including ones minted before this build.
    internal private(set) var liveReaderTokenCount = 0

    /// Whether the setup form must be replaced by reader identity controls.
    internal var isActive: Bool {
      liveReaderTokenCount > 0
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

    /// Counts live reader tokens while excluding persistent NFC registrations.
    internal func refresh() {
      guard Self.hasReaderSlot else {
        liveReaderTokenCount = 0
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
      let liveReaderTokenIdentifiers =
        refineIDTokenIdentifiers.subtracting(registeredTokenIdentifiers)

      liveReaderTokenCount = liveReaderTokenIdentifiers.count

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
