#if DEBUG

  import Foundation

  /// The one launch flag that lets an automated run past the biometric
  /// prompt.
  ///
  /// It exists for the UI tests, and nothing else reads it. Face ID cannot
  /// be satisfied programmatically on a physical device -- only the
  /// Simulator can be told to match a face -- so a test that drives card
  /// setup and priming on real hardware stops dead at the first prompt,
  /// with nothing on either side able to answer it. Every measurement that
  /// matters here is taken on real hardware with a real card, so the
  /// alternative is no automated measurement at all.
  ///
  /// Why that is safe: this declaration, the flag string, and the single
  /// line in ``CardCredentialGate`` that reads it all sit inside
  /// `#if DEBUG`. A TestFlight or Release build does not ignore the flag,
  /// it does not contain it -- there is no branch in a shipped binary that
  /// passing this string could reach. A debug build is never distributed
  /// and is already open to a debugger, which can do far more to a process
  /// than skip one prompt.
  ///
  /// It also grants less than it looks. The gate answers "is the device
  /// owner present"; it holds no credential, reads none, and returns none.
  /// Everything downstream -- PACE with the card access number, PIN1 at
  /// the card, the signature itself -- still has to be satisfied by the
  /// card.
  ///
  /// DEBUG only.
  internal enum DebugBiometricBypass {
    /// The flag a test runner passes to skip the biometric prompt.
    ///
    /// Keep in sync with `UITestApp.biometricBypassFlag` in
    /// `Tests/ReFineIDUITests`: a UI test drives another process and
    /// cannot share a constant with it.
    internal static let flag: String = "--skip-biometric-gate"

    /// Whether this launch was told to skip the prompt.
    internal static var isRequested: Bool {
      ProcessInfo.processInfo.arguments.contains(Self.flag)
    }
  }

#endif
