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
#if canImport(CoreNFC) && os(iOS)

  import Foundation

  /// The progress meter drawn inside the system NFC sheet.
  ///
  /// The sheet is where the holder is looking -- the card is against the
  /// phone and the app is behind Apple's own panel -- so this is where
  /// progress belongs. The panel takes no views: `update(message:)` is
  /// the entire drawing surface, one string.
  ///
  /// That string is short on purpose. The panel collapses a newline and
  /// truncates what will not fit on its line, so a meter followed by a
  /// sentence was measured rendering as the meter followed by an
  /// ellipsis -- the sentence lost, and a row of dots gained. The meter
  /// is therefore the whole message: five balls, filled as far as the
  /// hold has got.
  ///
  /// A failure is the exception, and there the sentence is all there is:
  /// a hold that is about to dismiss has one thing left to say and it is
  /// not how far it got.
  ///
  /// The markers are literal glyphs rather than escapes, by a deliberate
  /// exception to this repository's ASCII-only source rule: the sheet is
  /// a drawing surface made of text, and a table of escapes hides what
  /// it actually draws. Each one still names its codepoint.
  internal enum PrimingSheetMessage {
    /// U+1F535 LARGE BLUE CIRCLE: a step this hold has reached.
    private static let reached = "🔵"

    /// U+26AA MEDIUM WHITE CIRCLE: a step not yet reached.
    private static let waiting = "⚪"

    /// U+1F534 LARGE RED CIRCLE: a step that broke.
    private static let failed = "🔴"

    /// Thin space between markers, so five of them read as a row rather
    /// than one blob.
    private static let markerGap = " "

    /// The meter: one ball per step, as far as the hold has got.
    internal static func meter(
      states: [CardPrimingStep: CardPrimingStep.State]
    ) -> String {
      CardPrimingStep.allCases
        .map { Self.marker(states[$0] ?? .waiting) }
        .joined(separator: Self.markerGap)
    }

    /// The marker one step's state is drawn as.
    ///
    /// A step being worked on right now counts as reached: the holder is
    /// watching a row fill up, and splitting "started" from "finished"
    /// would add a third colour to answer a question nobody holding a
    /// card is asking.
    private static func marker(_ state: CardPrimingStep.State) -> String {
      switch state {
      case .done, .running:
        Self.reached
      case .failed:
        Self.failed
      case .waiting:
        Self.waiting
      }
    }
  }

#endif
