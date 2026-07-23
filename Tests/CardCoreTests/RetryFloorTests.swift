import CardCore
import Testing

@Suite
internal struct RetryFloorTests {
  @Test
  internal func unreadableFailsClosed() {
    #expect(RetryFloor.evaluate(freshReading: nil) == .refuseUnreadable)
  }

  @Test
  internal func zeroIsBlocked() throws {
    let reading = try #require(RetryCount(attemptsRemaining: 0))
    #expect(RetryFloor.evaluate(freshReading: reading) == .refuseBlocked)
  }

  @Test
  internal func everyCountBelowFloorRefusesWithoutBlocking() throws {
    for value in 1..<RetryFloor.minimumAttemptsToProceed {
      let reading = try #require(RetryCount(attemptsRemaining: value))
      #expect(RetryFloor.evaluate(freshReading: reading) == .refuseLowAttempts)
    }
  }

  @Test
  internal func everyCountAtOrAboveFloorProceeds() throws {
    for value in RetryFloor.minimumAttemptsToProceed...RetryCount.maximumPlausible {
      let reading = try #require(RetryCount(attemptsRemaining: value))
      #expect(RetryFloor.evaluate(freshReading: reading) == .proceed)
    }
  }

  @Test
  internal func floorIsAboveTheLastTwoAttempts() {
    // The invariant behind the numbers: the floor must keep at least two
    // attempts out of reach so ReFineID can never consume the last one.
    #expect(RetryFloor.minimumAttemptsToProceed >= 3)
  }
}
