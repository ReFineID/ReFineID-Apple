import CardCore
import CryptoTokenKit
import Security

/// Removes only the Safari identity state published by this app.
///
/// The holder's CAN and optional PIN1 remain stored. Reset is recovery
/// for a stale CryptoTokenKit registration, not a request to erase card
/// setup and force secret re-entry.
internal enum CardStateReset {
  /// One completed reset, including enough detail for diagnostics.
  internal struct Outcome {
    internal let lines: [String]
    internal let succeeded: Bool

    internal var summary: String {
      succeeded
        ? String(localized: "ReFineID's Safari card identities were reset.")
        : String(localized: "Some ReFineID Safari identity state could not be removed.")
    }
  }

  /// Clears registrations, identity configurations, primes, and trace.
  internal static func perform() -> Outcome {
    var lines = ["=== reset ReFineID Safari identities ==="]
    let registration = Self.unregisterOurTokens()
    lines += registration.lines

    let dropped = DriverConfiguredCredentials.dropIdentityTokenConfigurations()
    lines.append("ReFineID identity configurations removed: \(dropped)")

    PrimeStore.forgetAll()
    lines.append("ReFineID prime store: cleared")

    let traceStatus = ExtensionTrace.clear()
    let traceCleared = traceStatus == errSecSuccess || traceStatus == errSecItemNotFound
    lines.append(
      traceCleared
        ? "ReFineID extension trace: cleared"
        : "ReFineID extension trace: clear failed (\(traceStatus))")
    lines.append("Stored CAN and PIN1: preserved")
    lines.append("=== end ===")
    return Outcome(
      lines: lines,
      succeeded: registration.succeeded && traceCleared)
  }

  /// Unregisters only token IDs issued by this app's CTK class.
  private static func unregisterOurTokens() -> (
    lines: [String],
    succeeded: Bool
  ) {
    #if os(iOS)
      let manager = TKSmartCardTokenRegistrationManager.default
      let ours = manager.registeredSmartCardTokens
        .filter(CardTokenNamespace.owns(tokenIdentifier:))
        .sorted()
      guard !ours.isEmpty else {
        return (["ReFineID Safari registrations: none"], true)
      }
      var succeeded = true
      let lines = ours.map { tokenID in
        do {
          try manager.unregisterSmartCard(tokenID: tokenID)
          return "Unregistered \(tokenID)"
        } catch {
          succeeded = false
          return "Could not unregister \(tokenID): \(error)"
        }
      }
      return (lines, succeeded)
    #else
      return (["ReFineID Safari registrations: not used on this platform"], true)
    #endif
  }
}
