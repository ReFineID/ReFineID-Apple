/// The side-effect-free check before activation (FINEID S4-1 §4.6).
public enum ActivationPreflight {
  /// Evaluates readiness from counter-safe probes alone.
  ///
  /// Under the activation-code scheme (§4.6.1) PIN1 ships blocked, and
  /// the factory state answers the probe with nothing usable - so ANY
  /// live reading (remaining attempts, verified, locked, or
  /// invalidated) means the slot has been written to since
  /// manufacture, which is evidence of prior activation. A burned
  /// counter is such evidence too: locked is activated-then-exhausted,
  /// not factory-fresh.
  ///
  /// Under the preset-PIN scheme (§4.6.2) PIN1 ships set to the
  /// activation PIN, so a healthy counter is the expected fresh state
  /// and proves nothing. The changed-since-manufacture record is the
  /// authoritative signal; only `changed` blocks the flow, an
  /// unreadable record does not.
  public static func evaluate(
    scheme: ActivationScheme,
    pin1Probe: RetryProbeOutcome?,
    pin1ChangeRecord: PinChangeRecord
  ) -> ActivationReadiness {
    switch scheme {
    case .presetActivationPin:
      return pin1ChangeRecord == .changed ? .alreadyActivated : .ready
    case .activationCodeIsPuk:
      switch pin1Probe {
      case .remaining, .verified, .locked, .invalidated:
        return .alreadyActivated
      case .noInformation, .other, .none:
        return .ready
      }
    }
  }
}
