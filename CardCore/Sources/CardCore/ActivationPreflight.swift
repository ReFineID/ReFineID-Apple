/// The side-effect-free check before activation (FINEID S4-1 §4.6).
public enum ActivationPreflight {
  /// Evaluates readiness from counter-safe probes alone.
  ///
  /// Under the activation-code scheme (§4.6.1) both PINs ship blocked
  /// and the factory state answers the probe with nothing usable, so a
  /// live counter reading - remaining attempts, verified, or locked -
  /// means the slot has been written to since manufacture. Locked
  /// counts because it is activated-then-exhausted, not factory-fresh.
  ///
  /// An invalidated slot does NOT count. That is a state a card can be
  /// in before it was ever activated, and reading it as prior use
  /// would withhold activation from exactly the card that needs it.
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
      case .remaining, .verified, .locked:
        return .alreadyActivated
      case .invalidated, .noInformation, .other, .none:
        return .ready
      }
    }
  }
}
