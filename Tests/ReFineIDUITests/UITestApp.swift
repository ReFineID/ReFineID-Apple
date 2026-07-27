import XCTest

/// The app under test, launched the one way every test in this bundle
/// needs it.
///
/// One place decides what the app is told at launch, so a flag cannot be
/// present in one test and forgotten in the next -- a difference that
/// would show up as an unexplained prompt halfway through a run on a
/// device nobody is watching.
@MainActor
internal enum UITestApp {
  /// The DEBUG-only flag that lets automation past the biometric prompt.
  ///
  /// Keep in sync with `DebugBiometricBypass.flag` in
  /// `Sources/App/DebugBiometricBypass.swift`. Face ID cannot be satisfied
  /// programmatically on a physical device -- only the Simulator can --
  /// so without this every test that reaches a gated step stops at a
  /// prompt neither side can answer. The build being driven honours it
  /// only under `#if DEBUG`; a shipped build does not contain the branch.
  internal static let biometricBypassFlag = "--skip-biometric-gate"

  /// Launches the app under test and waits for it to be in front.
  internal static func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [Self.biometricBypassFlag]
    app.launch()
    return app
  }
}
