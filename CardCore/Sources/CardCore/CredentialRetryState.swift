/// One side-effect-free reading of all three retry counters.
public struct CredentialRetryState: Equatable, Sendable {
  /// Attempts remaining for PIN1.
  public let pin1: RetryCount

  /// Attempts remaining for PIN2.
  public let pin2: RetryCount

  /// Attempts remaining for the PUK.
  public let puk: RetryCount

  /// The named pristine state: PIN1/PIN2/PUK exactly 5/5/5.
  ///
  /// The reusable PIN1 cache is permitted only while a live reading is
  /// pristine (Documentation/release-plan.md section 4.2).
  public var isPristine: Bool {
    pin1.isPristine && pin2.isPristine && puk.isPristine
  }

  /// True when PIN1, PIN2, and PUK each keep at least the floor minimum.
  ///
  /// The card-health gate below which ReFineID refuses all service: a card
  /// degraded in any one dimension (PUK especially) is one bad event from
  /// unrecoverable, so we will not operate on it.
  public var allAboveFloor: Bool {
    pin1.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed
      && pin2.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed
      && puk.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed
  }

  /// Groups one simultaneous reading of the three counters.
  public init(pin1: RetryCount, pin2: RetryCount, puk: RetryCount) {
    self.pin1 = pin1
    self.pin2 = pin2
    self.puk = puk
  }
}
