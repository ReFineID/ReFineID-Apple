import CardCore
import Foundation
import Testing

/// Exercises the window's clock rule.
///
/// Only the rule is tested, not the keychain around it: storage needs an
/// entitlement this bundle does not carry, and the rule is where a
/// mistake would actually live.
@Suite
internal struct Pin1SigningWindowTests {
  /// The allowance, taken from the policy so this follows if it changes.
  private static var allowance: TimeInterval {
    Double(Pin1CachePolicy.idleTimeout.components.seconds)
  }

  private static let opened = Date(timeIntervalSince1970: 1_000_000)

  @Test
  internal func liveImmediatelyAfterUse() {
    #expect(Pin1SigningWindow.isLive(lastUsed: Self.opened, now: Self.opened))
  }

  @Test
  internal func liveJustInsideTheAllowance() {
    let now = Self.opened.addingTimeInterval(Self.allowance - 1)
    #expect(Pin1SigningWindow.isLive(lastUsed: Self.opened, now: now))
  }

  @Test
  internal func deadJustOutsideTheAllowance() {
    let now = Self.opened.addingTimeInterval(Self.allowance + 1)
    #expect(!Pin1SigningWindow.isLive(lastUsed: Self.opened, now: now))
  }

  @Test
  internal func theAllowanceIsFifteenMinutes() {
    #expect(Self.allowance == 15 * 60)
  }

  @Test
  internal func slidingKeepsAnActiveSessionOpen() {
    // Used near the end of the allowance, the window restamps, so a
    // moment past the ORIGINAL expiry is still live.
    let lastUse = Self.opened.addingTimeInterval(Self.allowance - 1)
    let pastOriginalExpiry = Self.opened.addingTimeInterval(Self.allowance + 1)
    #expect(Pin1SigningWindow.isLive(lastUsed: lastUse, now: pastOriginalExpiry))
  }

  @Test
  internal func aBackwardsClockCountsAsExpired() {
    let earlier = Self.opened.addingTimeInterval(-1)
    #expect(!Pin1SigningWindow.isLive(lastUsed: Self.opened, now: earlier))
  }
}
