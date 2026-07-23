/// Typed failures of card operations.
///
/// Transport-layer errors (reader gone, card pulled) propagate as the
/// channel's own thrown errors; these cases are protocol-level: the
/// card answered, and the answer was wrong.
public enum CardOperationError: Error, Equatable, Sendable {
  /// A response was shorter than a status word or beyond the
  /// short-form bound.
  case malformedResponse

  /// PIN1 verification was refused because the credential is blocked.
  case pinBlocked

  /// PIN1 was rejected; `remaining` attempts are left before it locks.
  case pinRejected(remaining: RetryCount)

  /// PIN1 VERIFY returned an unexpected status word.
  case pinVerifyFailed(StatusWord)

  /// A file read failed with the carried typed reason.
  case readFailed(BinaryReadFailure)

  /// A SELECT was answered with something other than success.
  case selectRejected(StatusWord)

  /// An exclusive card session could not be opened.
  case sessionUnavailable

  /// A signing command (MSE:SET or PSO:CDS) was refused.
  case signRejected(StatusWord)

  /// EF.TokenInfo was read but its content did not parse to a serial.
  case tokenInfoMalformed
}
