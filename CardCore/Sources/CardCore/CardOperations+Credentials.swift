import Foundation

/// The credential-bearing card operations: VERIFY, CHANGE REFERENCE
/// DATA, and RESET RETRY COUNTER.
///
/// Separate from the credential-free operations on purpose: every
/// parameter here is a noncopyable one-shot transmission, so one user
/// entry can reach the card at most once, and the caller must have
/// cleared the retry floor for whichever credential the command
/// presents.
extension CardOperations {
  /// Verifies PIN1, consuming the one-shot credential.
  ///
  /// Sends VERIFY with the padded PIN block (the noncopyable transport
  /// value guarantees at most one card command). Returns normally only
  /// on `9000`; a wrong PIN throws `pinRejected` carrying the remaining
  /// attempts, and any other answer throws `pinVerifyFailed`. The caller
  /// must already have cleared the retry floor.
  public func verifyPin1(_ transmission: consuming Pin1Transmission) throws {
    let command = CredentialBearingCommand.verifyPin1(transmission)
    let raw = try channel.transmit(command.intoTransportPayload())
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    switch response.statusWord {
    case .success:
      return
    case .pinIncorrect(let remaining):
      throw CardOperationError.pinRejected(remaining: remaining)
    case .authenticationBlocked:
      throw CardOperationError.pinBlocked
    default:
      throw CardOperationError.pinVerifyFailed(response.statusWord)
    }
  }

  /// Verifies PIN2, consuming the one-shot credential.
  ///
  /// PIN2 authorises the qualified-signature key; it is verified
  /// immediately before the one signature and never cached. Unlike the
  /// PIN1 path, an invalidated answer is an expected state here - a
  /// card whose signature slot was never activated gives it - so it
  /// maps to `credentialInvalidated`. The caller must already have
  /// cleared the retry floor.
  public func verifyPin2(_ transmission: consuming Pin2Transmission) throws {
    let command = CredentialBearingCommand.verifyPin2(transmission)
    let raw = try channel.transmit(command.intoTransportPayload())
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    switch response.statusWord {
    case .success:
      return
    case .pinIncorrect(let remaining):
      throw CardOperationError.pinRejected(remaining: remaining)
    case .authenticationBlocked:
      throw CardOperationError.pinBlocked
    case .referenceDataInvalidated:
      throw CardOperationError.credentialInvalidated
    default:
      throw CardOperationError.pinVerifyFailed(response.statusWord)
    }
  }

  /// Changes PIN1: the card checks `current` and replaces it with `new`
  /// in one command (CHANGE REFERENCE DATA, S1 v4.2 §3.5.3).
  ///
  /// On success the retry counter is at its maximum and the verified
  /// flag is cleared - the new PIN is set but not presented. A wrong
  /// current PIN throws `pinRejected` and costs one attempt; the caller
  /// must already have cleared the retry floor for PIN1.
  public func changePin1(
    current: consuming Pin1Transmission,
    new: consuming Pin1Transmission
  ) throws {
    try performCredentialUpdate(
      CredentialBearingCommand.changePin1(current: current, new: new)
    )
  }

  /// Changes PIN2: the card checks `current` and replaces it with `new`
  /// in one command (CHANGE REFERENCE DATA, S1 v4.2 §3.5.3).
  ///
  /// Same semantics as `changePin1`, against the PIN2 slot; the retry
  /// floor the caller must have cleared is PIN2's.
  public func changePin2(
    current: consuming Pin2Transmission,
    new: consuming Pin2Transmission
  ) throws {
    try performCredentialUpdate(
      CredentialBearingCommand.changePin2(current: current, new: new)
    )
  }

  /// Unblocks PIN1: the card checks the PUK, resets PIN1's retry
  /// counter, and sets `new` as its value (RESET RETRY COUNTER,
  /// S1 v4.2 §3.5.4).
  ///
  /// A wrong PUK throws `pinRejected` carrying the PUK's own remaining
  /// count, and exhausting the PUK is terminal for the card - the
  /// caller must have cleared the retry floor for the PUK, not the
  /// target PIN. On success the new PIN is set but not presented.
  public func unblockPin1(
    puk: consuming PukTransmission,
    new: consuming Pin1Transmission
  ) throws {
    try performCredentialUpdate(
      CredentialBearingCommand.unblockPin1(puk: puk, new: new)
    )
  }

  /// Unblocks PIN2: the card checks the PUK, resets PIN2's retry
  /// counter, and sets `new` as its value (RESET RETRY COUNTER,
  /// S1 v4.2 §3.5.4).
  ///
  /// Same semantics as `unblockPin1`, against the PIN2 slot.
  public func unblockPin2(
    puk: consuming PukTransmission,
    new: consuming Pin2Transmission
  ) throws {
    try performCredentialUpdate(
      CredentialBearingCommand.unblockPin2(puk: puk, new: new)
    )
  }

  /// Sends one credential update and classifies the card's answer: it
  /// either accepts, counts down the presented credential, or reports
  /// the slot blocked or invalidated.
  private func performCredentialUpdate(
    _ command: consuming CredentialBearingCommand
  ) throws {
    let raw = try channel.transmit(command.intoTransportPayload())
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    switch response.statusWord {
    case .success:
      return
    case .pinIncorrect(let remaining):
      throw CardOperationError.pinRejected(remaining: remaining)
    case .authenticationBlocked:
      throw CardOperationError.pinBlocked
    case .referenceDataInvalidated:
      throw CardOperationError.credentialInvalidated
    default:
      throw CardOperationError.credentialUpdateFailed(response.statusWord)
    }
  }
}
