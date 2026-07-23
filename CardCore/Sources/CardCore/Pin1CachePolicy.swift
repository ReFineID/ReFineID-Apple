/// Admission and lifetime policy for the reusable PIN1 cache.
///
/// Only PIN1 has a cache policy type; a PIN2 cache is unrepresentable in
/// this module by construction - no type exists that could hold one.
public enum Pin1CachePolicy {
  /// Minutes of idle time after which a cached PIN1 expires.
  private static let idleMinutes: Int64 = 15

  /// Seconds per minute.
  private static let secondsPerMinute: Int64 = 60

  /// The monotonic idle timeout: a cached entry expires this long after
  /// its last definite successful cached use.
  ///
  /// Status reads, lookups, prompts, and failed or uncertain operations
  /// never refresh it.
  public static let idleTimeout: Duration = .seconds(idleMinutes * secondsPerMinute)

  /// Pristine-only admission: a reusable PIN1 may exist only while a live
  /// reading of all three counters is exactly 5/5/5.
  ///
  /// A missing or unreadable reading admits nothing.
  public static func mayHoldReusableEntry(liveReading: CredentialRetryState?) -> Bool {
    liveReading?.isPristine ?? false
  }
}
