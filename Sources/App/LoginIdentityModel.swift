#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import SwiftUI

  /// Whether the system has a ReFineID login identity to offer right now.
  ///
  /// It observes and never touches the card, and that is the whole
  /// design rather than an optimisation. A card is exclusive: a status
  /// screen that opens a session to read a card holds it, and the token
  /// extension's signature then waits for this app to let go. That wait
  /// is the one thing no protocol timer bounds -- it is not the card
  /// being slow, it is another process not answering -- and on
  /// 2026-08-03 it was measured hanging a Safari login at the PIN1
  /// retry-floor probe until the app was quit. A window that reads no
  /// card cannot do that to a login.
  ///
  /// `TKTokenWatcher` reports what `ctkd` has already published, so the
  /// answer costs nothing and stays live: a card arriving or leaving
  /// moves it without anyone pressing refresh.
  @MainActor
  @Observable
  internal final class LoginIdentityModel {
    /// Watches publication and removal.
    ///
    /// No card I/O of any kind.
    private let watcher = TKTokenWatcher()

    /// Token ids already given a removal handler, so each is asked once.
    private var observed: Set<String> = []

    /// Whether Safari can be offered an identity from this card.
    internal private(set) var isReady = false

    internal init() {
      watcher.setInsertionHandler(Self.insertionHandler(for: self))
      refresh()
    }

    /// Builds a `ctkd` callback with no inherited main-actor isolation.
    ///
    /// `TKTokenWatcher` invokes this on its own XPC queue. Constructing
    /// the block inside this main-actor type makes Swift trap before the
    /// body can hop to the intended actor.
    nonisolated private static func insertionHandler(
      for model: LoginIdentityModel
    ) -> @Sendable (String) -> Void {
      { [weak model] _ in
        Task { @MainActor [weak model] in
          model?.refresh()
        }
      }
    }

    /// The same, for a token going away.
    nonisolated private static func removalHandler(
      for model: LoginIdentityModel
    ) -> @Sendable (String) -> Void {
      { [weak model] removed in
        Task { @MainActor [weak model] in
          model?.observed.remove(removed)
          model?.refresh()
        }
      }
    }

    /// Re-reads what is published and keeps watching what is there.
    internal func refresh() {
      isReady = CardStatusSnapshot.publishesAnIdentity()
      for identifier in watcher.tokenIDs
      where CardTokenNamespace.owns(tokenIdentifier: identifier) {
        guard observed.insert(identifier).inserted else { continue }
        watcher.addRemovalHandler(Self.removalHandler(for: self), forTokenID: identifier)
      }
    }
  }

#endif
