import CardCore
import Testing

/// The production guard, stated once as a table.
///
/// Every PIN-bearing operation reads the counter of the credential it
/// is about to present, in the same card transaction, and proceeds
/// only on this rule. The test exists because the rule is the thing
/// standing between a curious afternoon - or a bug in this code - and
/// a card that has to go back to the issuer.
@Suite
internal struct RetryFloorPolicyTests {
  @Test
  internal func theFloorRefusesExactlyOneAndTwoAttempts() throws {
    // Three or more: room to be wrong and try again.
    for remaining in [UInt8(3), 4, 5] {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(RetryFloor.evaluate(freshReading: count) == .proceed)
    }
    // One or two: refused. Never spend a near-last attempt.
    for remaining in [UInt8(1), 2] {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(RetryFloor.evaluate(freshReading: count) == .refuseLowAttempts)
    }
    // Zero: already blocked. Not our refusal to make - and the state
    // the PUK exists to undo, which is why it is named apart.
    let blocked = try #require(RetryCount(attemptsRemaining: 0))
    #expect(RetryFloor.evaluate(freshReading: blocked) == .refuseBlocked)
  }

  @Test
  internal func anUnreadableCounterFailsClosed() {
    // No reading is not permission. A probe that cannot be classified
    // must never become an attempt.
    #expect(RetryFloor.evaluate(freshReading: nil) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .noInformation) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .other(0)) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .invalidated) == .refuseUnreadable)
    // A verified credential reports no count at all, so it is no
    // licence either.
    #expect(RetryFloor.evaluate(probeOutcome: .verified) == .refuseUnreadable)
  }

  @Test
  internal func aLockedCredentialIsNamedApartFromAnUnreadableOne() {
    // The two are different answers to the holder: one says unblock it,
    // the other says the card could not be read. Collapsing them would
    // send someone to the issuer for a reader fault.
    #expect(RetryFloor.evaluate(probeOutcome: .locked) == .refuseBlocked)
  }

  @Test
  internal func eachCredentialIsJudgedOnItsOwnCounter() throws {
    // The three counters are never combined. A PUK with room is what
    // permits an unblock, whatever the blocked PIN says; a PIN2 near
    // its limit refuses a signature while PIN1 is untouched.
    let blocked = try #require(RetryCount(attemptsRemaining: 0))
    let low = try #require(RetryCount(attemptsRemaining: 2))
    let healthy = try #require(RetryCount(attemptsRemaining: 5))
    let state = CredentialRetryState(pin1: blocked, pin2: low, puk: healthy)
    #expect(RetryFloor.evaluate(freshReading: state.pin1) == .refuseBlocked)
    #expect(RetryFloor.evaluate(freshReading: state.pin2) == .refuseLowAttempts)
    #expect(RetryFloor.evaluate(freshReading: state.puk) == .proceed)
  }
}
