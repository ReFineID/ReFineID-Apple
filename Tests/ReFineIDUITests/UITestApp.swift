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
  /// Launches the app under test in a stated language.
  ///
  /// The language is pinned rather than inherited. A run on a Mac set
  /// to Finnish draws Finnish control titles, and a test that matched
  /// the English title found no control at all and blamed the window.
  /// Naming the language keeps a matched title a fact about the app
  /// rather than about the machine, and lets a test ask for a
  /// translation deliberately.
  internal static func launch() -> XCUIApplication {
    Self.launch(language: "en")
  }

  /// Launches the app under test in the named language.
  internal static func launch(language: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(\(language))"]
    app.launch()
    return app
  }
}
