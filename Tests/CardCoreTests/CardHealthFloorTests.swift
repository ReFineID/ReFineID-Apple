import CardCore
import Testing

@Suite
internal struct CardHealthFloorTests {
  private func count(_ value: UInt8) -> RetryCount {
    guard let count = RetryCount(attemptsRemaining: value) else {
      fatalError("test retry count must be valid")
    }
    return count
  }

  private func report(pin1: UInt8, pin2: UInt8, puk: UInt8) -> CredentialProbeReport {
    CredentialProbeReport(
      pin1: .remaining(count(pin1)),
      pin2: .remaining(count(pin2)),
      puk: .remaining(count(puk))
    )
  }

  @Test
  internal func pristineCardProceeds() {
    #expect(RetryFloor.evaluateAll(report(pin1: 5, pin2: 5, puk: 5)) == .proceed)
  }

  @Test
  internal func allAtTheFloorProceeds() {
    #expect(RetryFloor.evaluateAll(report(pin1: 3, pin2: 3, puk: 3)) == .proceed)
  }

  @Test
  internal func anyCredentialBelowTheFloorRefuses() {
    #expect(RetryFloor.evaluateAll(report(pin1: 2, pin2: 5, puk: 5)) == .refuseLowAttempts)
    #expect(RetryFloor.evaluateAll(report(pin1: 5, pin2: 2, puk: 5)) == .refuseLowAttempts)
    // PUK specifically: a low PUK refuses even with healthy PINs.
    #expect(RetryFloor.evaluateAll(report(pin1: 5, pin2: 5, puk: 2)) == .refuseLowAttempts)
  }

  @Test
  internal func anyUnreadableCredentialFailsClosed() {
    let lockedPin1 = CredentialProbeReport(
      pin1: .locked,
      pin2: .remaining(count(5)),
      puk: .remaining(count(5))
    )
    #expect(RetryFloor.evaluateAll(lockedPin1) == .refuseUnreadable)
    let noPukCounter = CredentialProbeReport(
      pin1: .remaining(count(5)),
      pin2: .remaining(count(5)),
      puk: .noInformation
    )
    #expect(RetryFloor.evaluateAll(noPukCounter) == .refuseUnreadable)
  }
}
