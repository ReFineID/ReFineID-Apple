import Synchronization

/// Process-lifetime, card-bound PIN1 cache.
///
/// Caches the *PIN sheet*, never the *card VERIFY*: every signature
/// still sends VERIFY PIN1 to the card; the cache only spares the user
/// re-typing across the several signs of one login flow.
///
/// Cannot lock a card because it only ever holds a PIN the card just
/// accepted, so every reuse verifies and never decrements, and:
///
/// - it is bound to the full card **serial**, re-read and matched before
///   every reuse - a cached PIN can never reach a different card;
/// - it is **pristine-gated**: reuse requires a live 5/5/5 reading, and a
///   non-pristine reading latches caching off until `reset` (a fresh
///   token when the card re-appears);
/// - it carries a **monotonic idle timestamp** validated lazily on use;
/// - it lives only in memory, in a zeroizing store, and is never
///   persisted. In practice the OS reaps this extension process between
///   login flows, so the entry rarely survives to the idle window at all.
public final class Pin1Cache: Sendable {
  /// One cached PIN1, bound to a card and stamped for idle expiry.
  private struct Entry {
    let digits: ZeroizingDigitStore
    let serial: TokenSerial
    var stamp: ContinuousClock.Instant
  }

  /// Mutable cache state behind the mutex.
  private struct State {
    var entry: Entry?
    var enabled: Bool
  }

  /// The default idle window in seconds: fifteen minutes.
  private static let defaultIdleWindowSeconds = 900

  /// Max idle gap between signs before a cached PIN1 expires (15 minutes).
  public static let defaultIdleWindow: Duration = .seconds(defaultIdleWindowSeconds)

  private let idleWindow: Duration
  private let clock = ContinuousClock()
  private let state = Mutex(State(entry: nil, enabled: true))

  /// Creates an empty, enabled cache; the driver owns one per process.
  ///
  /// `idleWindow` is injectable for tests; production uses the 15-minute
  /// default.
  public init(idleWindow: Duration = Pin1Cache.defaultIdleWindow) {
    self.idleWindow = idleWindow
  }

  /// A reusable PIN1 for `serial` when a live entry is valid, else nil
  /// (the caller must prompt).
  ///
  /// Validated in order: caching enabled, same serial, within the idle
  /// window, and `pristine`. A serial mismatch or idle expiry just drops
  /// the entry (caching stays on); a non-pristine reading also **latches
  /// caching off** until `reset`.
  public func checkout(serial: TokenSerial, pristine: Bool) -> Pin1? {
    let reusable: ZeroizingDigitStore? = state.withLock { state in
      guard state.enabled, let entry = state.entry else { return nil }
      guard entry.serial == serial else {
        state.entry = nil
        return nil
      }
      guard clock.now - entry.stamp <= self.idleWindow else {
        state.entry = nil
        return nil
      }
      guard pristine else {
        state.entry = nil
        state.enabled = false
        return nil
      }
      return ZeroizingDigitStore(bytes: entry.digits.bytes)
    }
    guard let reusable else { return nil }
    return Pin1(owning: reusable)
  }

  /// Stores a freshly-entered PIN1, replacing any prior entry.
  ///
  /// Stamps to now; no-op while caching is latched off. The caller stores
  /// only after a successful sign on a pristine card.
  public func store(_ pin: borrowing Pin1, serial: TokenSerial) {
    let digits = pin.cachedCopy()
    state.withLock { state in
      guard state.enabled else { return }
      state.entry = Entry(digits: digits, serial: serial, stamp: clock.now)
    }
  }

  /// Refreshes the idle timestamp after a successful reuse.
  ///
  /// The sliding window; no-op if the entry is gone or bound to another
  /// serial.
  public func restamp(serial: TokenSerial) {
    state.withLock { state in
      guard state.entry?.serial == serial else { return }
      state.entry?.stamp = clock.now
    }
  }

  /// Drops any cached PIN1 without touching the enable latch - for a
  /// wrong PIN or any per-sign invalidation.
  public func clear() {
    state.withLock { state in
      state.entry = nil
    }
  }

  /// Clears the cache and re-enables caching, for a fresh token.
  ///
  /// The "until the token appears again" reset after a latched-off
  /// degradation, when the card re-appears.
  public func reset() {
    state.withLock { state in
      state.entry = nil
      state.enabled = true
    }
  }
}
