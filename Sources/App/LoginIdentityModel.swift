#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import os.log
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
    /// What the login row can truthfully say.
    internal enum Availability: Equatable {
      /// A card is in the reader but no identity is offered from it
      /// - the state after a driver update, until the card is seen
      /// again.
      case cardWithoutIdentity

      /// No card in any reader.
      case noCard

      /// An identity is published and Safari can be offered it.
      case ready
    }

    /// Watcher outcomes, visible in the unified log for field reports.
    ///
    /// Counts and booleans only; never an identifier.
    private static let log = Logger(
      subsystem: "fi.refineid.ReFineID", category: "login-identity"
    )

    /// The one instance, built once for the process.
    ///
    /// Not a `@State` default. SwiftUI evaluates a `@State` default
    /// expression on every `init` of the view that declares it -
    /// which is every re-render - and keeps only the first. Building
    /// this model there meant every re-render ran a keychain query
    /// and installed another `TKTokenWatcher` handler, and those
    /// handlers fired refreshes that caused more re-renders. Measured
    /// on 2026-08-04 at about nine hundred keychain queries a second,
    /// which starved `ctkd` and blocked other applications' card use:
    /// Adobe Acrobat hung for thirty-five seconds inside
    /// CryptoTokenKit waiting for a session this app was crowding
    /// out.
    internal static let shared = LoginIdentityModel()

    /// Seconds the unready state must persist before the software
    /// reinsertion is tried.
    private static let recoveryDelaySeconds = 3

    /// The same, as the sleep wants it.
    private static let recoveryDelay: Duration = .seconds(recoveryDelaySeconds)
    /// The credential entry the app itself publishes, which the
    /// system lists as a token without it ever being a card.
    private static let credentialEntryPrefix =
      CardTokenNamespace.tokenPrefix
      + DriverConfiguredCredentials.configurationInstanceID

    /// Watches publication and removal.
    ///
    /// No card I/O of any kind.
    private let watcher = TKTokenWatcher()

    /// The recovery attempt in flight, if any.
    @ObservationIgnored private var recovery: Task<Void, Never>?

    /// Whether recovery was already tried for this card appearance.
    @ObservationIgnored private var attempted = false

    /// Token ids already given a removal handler, so each is asked once.
    private var observed: Set<String> = []

    /// Whether Safari can be offered an identity from this card.
    internal private(set) var isReady = false

    /// Counts the refreshes, so a row that keys on it re-reads what
    /// it shows whenever the token listing moves - a re-mint after a
    /// driver update changes what a name read answers without ever
    /// changing `isReady`.
    internal private(set) var generation = 0

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

    /// The software shape of pulling the card: begin one session on
    /// each present card and end it at once.
    nonisolated private static func touchPresentCard() async {
      guard let manager = TKSmartCardSlotManager.default else { return }
      for name in manager.slotNames {
        guard
          let slot = manager.slotNamed(name),
          slot.state == .validCard,
          let card = slot.makeSmartCard()
        else { continue }
        // Ending a session that never began trips an assertion inside
        // TKSmartCard, which raises an exception nothing catches and
        // takes the process with it. The card can leave between the
        // state read above and this call, so the session is ended only
        // when the card says it opened one.
        guard let opened = try? await card.beginSession(), opened else { continue }
        card.endSession()
      }
    }

    /// Re-reads what is published and keeps watching what is there.
    ///
    /// The model's own watcher is the source: it is connected and
    /// event-fed, so its listing is current at every call. A watcher
    /// built fresh for the question answers empty until its connection
    /// comes up - which at launch, with the card already in the
    /// reader, is exactly when the question is asked.
    internal func refresh() {
      generation += 1
      let listed = watcher.tokenIDs
      isReady = listed.contains { identifier in
        CardTokenNamespace.owns(tokenIdentifier: identifier)
          && !identifier.hasPrefix(Self.credentialEntryPrefix)
      }
      Self.log.info(
        "refresh: \(listed.count) listed, ready \(self.isReady)"
      )
      for identifier in watcher.tokenIDs
      where CardTokenNamespace.owns(tokenIdentifier: identifier) {
        guard observed.insert(identifier).inserted else { continue }
        watcher.addRemovalHandler(Self.removalHandler(for: self), forTokenID: identifier)
      }
    }

    /// Schedules one software "reinsertion" for this card appearance.
    ///
    /// The no-card-I/O rule above has exactly one exception, taken
    /// only in the state it exists to prevent: a card in the reader
    /// with no identity published from it. Pulling the card is what
    /// recovers that state, because the card-status change makes
    /// `ctkd` ask the driver again - and opening one brief session
    /// and closing it produces the same status change in software.
    /// It runs only while nothing is published, so there is no token
    /// whose signature could be made to wait, and once per
    /// appearance, so a card the driver genuinely cannot serve is
    /// not prodded forever.
    internal func attemptRecovery(unresolvedIdentity: Bool) {
      guard !attempted, recovery == nil else { return }
      recovery = Task { @MainActor [weak self] in
        try? await Task.sleep(for: Self.recoveryDelay)
        guard let self, !Task.isCancelled else { return }
        // Ready with a resolvable identity needs nothing. Ready with
        // an identity the keychain cannot resolve is the shape a
        // driver update leaves behind - a listed token whose items
        // return with the next card appearance - and the same
        // software reinsertion recovers it. The row reports that
        // shape rather than this task re-asking the keychain: in the
        // phantom state the asking itself is what hangs.
        guard !isReady || unresolvedIdentity else {
          recovery = nil
          return
        }
        attempted = true
        await Self.touchPresentCard()
        recovery = nil
        refresh()
      }
    }

    /// Stops any scheduled recovery; a card that left resets the
    /// once-per-appearance budget.
    internal func cancelRecovery(cardLeft: Bool) {
      recovery?.cancel()
      recovery = nil
      if cardLeft {
        attempted = false
      }
    }
  }

#endif
