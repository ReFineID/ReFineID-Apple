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
  /// Launches the app under test and waits for it to be in front.
  internal static func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launch()
    return app
  }
}
