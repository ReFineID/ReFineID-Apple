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

  /// Decides from a probe taken over a secure channel, where the card may
  /// decline to answer for a credential at all.
  ///
  /// A FINEID card refuses the PUK counter on its contactless interface,
  /// answering SW 6988 -- an access refusal, not a reading of the
  /// counter. `evaluateAll` cannot tell those apart and fails closed on
  /// both, which refuses service to a perfectly healthy card for the
  /// whole of an interface: measured as pin1=5, pin2=5, puk=6988.
  ///
  /// So this distinguishes them. PIN1 must still be readable and above
  /// the floor, because PIN1 is the credential this operation spends and
  /// the one that can be driven toward blocking. A counter the card
  /// declines to report is left out of the verdict rather than read as
  /// zero; a counter it does report is held to the same floor as
  /// anywhere else.
  public static func evaluateReported(_ report: CredentialProbeReport) -> RetryFloorVerdict {
    guard case .remaining(let pin1) = report.pin1 else {
      return Self.evaluate(freshReading: nil)
    }
    let verdict = Self.evaluate(freshReading: pin1)
    guard verdict == .proceed else { return verdict }
    for reported in [report.pin2, report.puk] {
      guard case .remaining(let count) = reported else { continue }
      let other = Self.evaluate(freshReading: count)
      guard other == .proceed else { return other }
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
