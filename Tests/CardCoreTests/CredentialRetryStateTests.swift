import CardCore
import Testing

@Suite
internal struct CredentialRetryStateTests {
  @Test
  internal func fiveFiveFiveIsPristine() throws {
    let state = try CredentialRetryState(
      pin1: count(RetryCount.pristineAllowance),
      pin2: count(RetryCount.pristineAllowance),
      puk: count(RetryCount.pristineAllowance)
    )
    #expect(state.isPristine)
  }

  @Test
  internal func anySingleConsumedAttemptBreaksPristine() throws {
    let notPristine = try count(RetryCount.pristineAllowance - 1)
    let pristine = try count(RetryCount.pristineAllowance)

    let states = [
      CredentialRetryState(pin1: notPristine, pin2: pristine, puk: pristine),
      CredentialRetryState(pin1: pristine, pin2: notPristine, puk: pristine),
      CredentialRetryState(pin1: pristine, pin2: pristine, puk: notPristine),
    ]
    for state in states {
      #expect(!state.isPristine)
    }
  }

  @Test
  internal func aboveAllowanceIsNotPristine() throws {
    // A counter above five is representable (some profiles could differ)
    // but must never satisfy the 5/5/5 cache precondition.
    let state = try CredentialRetryState(
      pin1: count(RetryCount.pristineAllowance + 1),
      pin2: count(RetryCount.pristineAllowance),
      puk: count(RetryCount.pristineAllowance)
    )
    #expect(!state.isPristine)
  }

  private func count(_ value: UInt8) throws -> RetryCount {
    try #require(RetryCount(attemptsRemaining: value))
  }
}
