import CardCore
import Testing

@Suite
internal struct Pin1CachePolicyTests {
  @Test
  internal func pristineAdmits() throws {
    let state = try CredentialRetryState(
      pin1: count(RetryCount.pristineAllowance),
      pin2: count(RetryCount.pristineAllowance),
      puk: count(RetryCount.pristineAllowance)
    )
    #expect(Pin1CachePolicy.mayHoldReusableEntry(liveReading: state))
  }

  @Test
  internal func missingReadingAdmitsNothing() {
    #expect(!Pin1CachePolicy.mayHoldReusableEntry(liveReading: nil))
  }

  @Test
  internal func anyNonPristineCounterRefuses() throws {
    let consumed = try count(RetryCount.pristineAllowance - 1)
    let above = try count(RetryCount.pristineAllowance + 1)
    let pristine = try count(RetryCount.pristineAllowance)

    let states = [
      CredentialRetryState(pin1: consumed, pin2: pristine, puk: pristine),
      CredentialRetryState(pin1: pristine, pin2: consumed, puk: pristine),
      CredentialRetryState(pin1: pristine, pin2: pristine, puk: consumed),
      CredentialRetryState(pin1: above, pin2: pristine, puk: pristine),
    ]
    for state in states {
      #expect(!Pin1CachePolicy.mayHoldReusableEntry(liveReading: state))
    }
  }

  @Test
  internal func idleTimeoutIsFifteenMinutes() {
    let fifteenMinutesInSeconds = 900
    #expect(Pin1CachePolicy.idleTimeout == .seconds(fifteenMinutesInSeconds))
  }

  private func count(_ value: UInt8) throws -> RetryCount {
    try #require(RetryCount(attemptsRemaining: value))
  }
}
