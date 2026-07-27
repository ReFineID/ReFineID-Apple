/// One counter-safe reading of all three credentials.
public struct CredentialProbeReport: Equatable, Sendable {
  /// PIN1 probe outcome (VERIFY probe form).
  public let pin1: RetryProbeOutcome

  /// PIN2 probe outcome (VERIFY probe form).
  public let pin2: RetryProbeOutcome

  /// PUK probe outcome (GET DATA PIN-container form).
  public let puk: RetryProbeOutcome

  /// Whether every counter the card reported is at its pristine
  /// allowance, with PIN1 and PIN2 among them.
  ///
  /// `retryState` needs all three and is nil without them, which on the
  /// contactless interface it always is: the card refuses the PUK
  /// counter there, so a reading that is genuinely 5/5 reads as "no
  /// state" and every cache admission is refused -- meaning a PIN
  /// prompt per signature, for a card in perfect health.
  ///
  /// A counter that was never reported is therefore left out of the
  /// judgement rather than counted as degraded. PIN1 and PIN2 must both
  /// be reported and pristine, because those are the counters this app
  /// can actually move.
  public var reportedCountersArePristine: Bool {
    guard
      case .remaining(let pin1Count) = pin1,
      case .remaining(let pin2Count) = pin2,
      pin1Count.isPristine, pin2Count.isPristine
    else {
      return false
    }
    guard case .remaining(let pukCount) = puk else { return true }
    return pukCount.isPristine
  }

  /// The typed retry state, available only when all three probes
  /// returned counters.
  ///
  /// The contact interface is the only one that can produce it: see
  /// `reportedCountersArePristine` for why the contactless one cannot.
  public var retryState: CredentialRetryState? {
    guard
      case .remaining(let pin1Count) = pin1,
      case .remaining(let pin2Count) = pin2,
      case .remaining(let pukCount) = puk
    else {
      return nil
    }
    return CredentialRetryState(pin1: pin1Count, pin2: pin2Count, puk: pukCount)
  }

  /// Groups one simultaneous probe of the three credentials.
  public init(
    pin1: RetryProbeOutcome,
    pin2: RetryProbeOutcome,
    puk: RetryProbeOutcome
  ) {
    self.pin1 = pin1
    self.pin2 = pin2
    self.puk = puk
  }
}
