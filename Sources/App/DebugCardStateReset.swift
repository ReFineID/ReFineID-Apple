#if DEBUG

  import CardCore
  import CryptoTokenKit

  /// Returns this device to a known zero before a measurement.
  ///
  /// Every measurement starts from zero or it is not a measurement. A
  /// smart-card token registered by yesterday's build answers the query
  /// today's build was meant to answer; a prime record written before a
  /// contents-version bump serves a login that should have failed; an open
  /// signing window makes an unattended signature look like a working PIN
  /// path; and an old trace line reads as if this run had produced it. Each
  /// of those has cost a wrong conclusion, so the reset clears all four and
  /// then prints what is left.
  ///
  /// What it does NOT clear is the stored card access number and PIN1.
  /// Those are the holder's own setup rather than measured state, and
  /// dropping them would make every reset cost a re-entry -- which is
  /// exactly the friction that stops a reset from being run.
  ///
  /// DEBUG only.
  ///
  /// Provenance: `--ctk-reset` in the donor
  /// `platform/apple/RefineID/Shared/RefineIDApp.swift`.
  internal enum DebugCardStateReset {
    /// Prefix every token identifier this project publishes carries.
    ///
    /// Only ours are unregistered. A device may carry another vendor's
    /// smart-card token, and tearing that down would be someone else's
    /// login broken by our debugging.
    private static let tokenPrefix: String = "fi.refineid."

    /// Line break the diagnostics snapshot's text form uses.
    private static let newline: String = "\n"

    /// Clears the measured state and reports what remains.
    internal static func perform() -> [String] {
      var lines = ["=== reset card state ==="]
      lines += Self.unregisterOurTokens()
      PrimeStore.forgetAll()
      lines.append("prime store: cleared")
      Pin1SigningWindow.close()
      lines.append("signing window: closed")
      ExtensionTrace.clear()
      lines.append("extension trace: cleared")
      lines += Self.remainingLines()
      lines.append("=== end ===")
      return lines
    }

    /// Unregisters every smart-card token whose identifier is ours.
    private static func unregisterOurTokens() -> [String] {
      #if os(iOS)
        let manager = TKSmartCardTokenRegistrationManager.default
        let ours = manager.registeredSmartCardTokens
          .filter { $0.hasPrefix(Self.tokenPrefix) }
          .sorted()
        guard !ours.isEmpty else {
          return ["registered smart cards: none of ours to unregister"]
        }
        return ours.map { tokenID in
          do {
            try manager.unregisterSmartCard(tokenID: tokenID)
            return "unregistered \(tokenID)"
          } catch {
            return "unregister \(tokenID) FAILED: \(error)"
          }
        }
      #else
        return ["registered smart cards: not available on this platform"]
      #endif
    }

    /// The state a following measurement will actually start from.
    ///
    /// Read through the same snapshot the diagnostics screen uses, so the
    /// zero this claims to have reached is the zero everything else would
    /// report. A reset that graded its own work with its own ruler would be
    /// worth nothing.
    private static func remainingLines() -> [String] {
      ["-- state now --"]
        + DiagnosticsSnapshot.collect().text.components(separatedBy: Self.newline)
    }
  }

#endif
