// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

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
