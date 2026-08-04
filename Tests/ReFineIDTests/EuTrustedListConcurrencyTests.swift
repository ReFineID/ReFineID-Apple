import Foundation
import Testing

@testable import ReFineID

/// Direct checks for bounded national-list scheduling and retry behavior.
@Suite
internal struct EuTrustedListConcurrencyTests {
  /// Tracks concurrent work and per-input attempts.
  private actor Probe {
    private var active = 0
    private var attempts: [Int: Int] = [:]
    private var peak = 0

    /// Marks one operation active and returns this input's attempt number.
    func begin(_ input: Int) -> Int {
      active += 1
      attempts[input, default: 0] += 1
      peak = max(peak, active)
      return attempts[input, default: 0]
    }

    /// Marks one operation complete.
    func end() {
      active -= 1
    }

    /// Number of attempts made for one input.
    func attemptCount(for input: Int) -> Int {
      attempts[input, default: 0]
    }

    /// Highest number observed concurrently.
    func maximum() -> Int { peak }
  }

  /// Sentinel used by the generic test operation to signal failure.
  private static let failedValue = -1

  /// National-list work preserves pointer order while never exceeding
  /// the production four-job resource bound.
  @Test
  internal func schedulerCapsConcurrencyAndPreservesOrder() async {
    let inputs = Array(0..<12)
    let probe = Probe()

    let outputs = await EuTrustedListDirectory.mapBounded(
      inputs,
      maximumConcurrency:
        EuTrustedListDirectory.maximumConcurrentNationalLists
    ) { value in
      _ = await probe.begin(value)
      try? await Task.sleep(for: .milliseconds(20))
      await probe.end()
      return value * 2
    }
    let peak = await probe.maximum()

    #expect(outputs == inputs.map { $0 * 2 })
    #expect(peak == EuTrustedListDirectory.maximumConcurrentNationalLists)
  }

  /// Exactly the initially failed input is retried once and replaced in
  /// its original result position.
  @Test
  internal func retryPassRunsOnlyForFailuresAndPreservesOrder() async {
    let inputs = [0, 1, 2]
    let probe = Probe()

    let outputs = await EuTrustedListDirectory.mapRetryingFailures(
      inputs,
      maximumConcurrency:
        EuTrustedListDirectory.maximumConcurrentNationalLists,
      isFailure: { $0 == Self.failedValue },
      operation: { value in
        let attempt = await probe.begin(value)
        await probe.end()
        if value == 1, attempt == 1 { return Self.failedValue }
        return value
      }
    )
    let firstAttempts = await probe.attemptCount(for: 0)
    let failedAttempts = await probe.attemptCount(for: 1)
    let lastAttempts = await probe.attemptCount(for: 2)

    #expect(outputs == inputs)
    #expect(firstAttempts == 1)
    #expect(failedAttempts == 2)
    #expect(lastAttempts == 1)
  }
}
