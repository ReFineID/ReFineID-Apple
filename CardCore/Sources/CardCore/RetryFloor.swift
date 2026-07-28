/// Every CTK PIN-bearing command obtains fresh retry state first,
/// side-effect-free, and this rule decides whether the operation may proceed.
public enum RetryFloor {
  /// An operation proceeds only when at least this many attempts remain.
  public static let minimumAttemptsToProceed: UInt8 = 3

  /// Decides from one fresh reading.
  ///
  /// Pass nil when the state could not be read or did not parse - the
  /// verdict then fails closed.
  ///
  /// Freshness is the caller's obligation: the reading must come from the
  /// same exclusive card transaction that will carry the PIN command,
  /// immediately before it.
  public static func evaluate(freshReading: RetryCount?) -> RetryFloorVerdict {
    guard let reading = freshReading else { return .refuseUnreadable }
    if reading.isBlocked { return .refuseBlocked }
    if reading.attemptsRemaining < Self.minimumAttemptsToProceed {
      return .refuseLowAttempts
    }
    return .proceed
  }

  /// Decides from one credential's side-effect-free probe outcome.
  ///
  /// A terminal lock is distinct from an unreadable response so the
  /// caller can diagnose it without consulting unrelated credentials.
  public static func evaluate(probeOutcome: RetryProbeOutcome) -> RetryFloorVerdict {
    switch probeOutcome {
    case .remaining(let reading):
      return evaluate(freshReading: reading)
    case .locked:
      return .refuseBlocked
    case .invalidated, .noInformation, .other, .verified:
      return .refuseUnreadable
    }
  }
}
