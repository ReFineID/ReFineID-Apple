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

  /// Decides from one fresh all-three probe.
  ///
  /// Proceeds only when PIN1, PIN2, and PUK are each readable and at or
  /// above the minimum; any counter low, blocked, or unreadable fails
  /// closed - a card degraded in any dimension is refused service entirely
  /// (Documentation/release-plan.md §4.1).
  public static func evaluateAll(_ report: CredentialProbeReport) -> RetryFloorVerdict {
    guard let state = report.retryState else { return .refuseUnreadable }
    return state.allAboveFloor ? .proceed : .refuseLowAttempts
  }
}
