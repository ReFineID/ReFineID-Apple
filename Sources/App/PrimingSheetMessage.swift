#if canImport(CoreNFC) && os(iOS)

  import Foundation

  /// The progress meter drawn inside the system NFC sheet.
  ///
  /// The sheet is where the holder is looking -- the card is against the
  /// phone and the app is behind Apple's own panel -- so this is where
  /// progress belongs. The panel takes no views: `update(message:)` is
  /// the entire drawing surface, one string. So the meter IS the string,
  /// one marker per step followed by the sentence for the step running
  /// now.
  ///
  /// The markers are chosen so shape and colour each carry the state on
  /// their own: a check inside a filled ball for done, a cross for
  /// failed, a filled ball for running, an empty ball for not yet
  /// reached. Roughly one man in twelve cannot separate green from red,
  /// and a meter they cannot read is not a meter.
  ///
  /// The markers are literal glyphs rather than escapes, by a
  /// deliberate exception to this repository's ASCII-only source rule:
  /// the sheet is a drawing surface made of text, and a table of escapes
  /// hides what it actually draws. Each one still names its codepoint.
  internal enum PrimingSheetMessage {
    /// U+2705 WHITE HEAVY CHECK MARK: a check inside a green ball.
    private static let done = "✅"

    /// U+274C CROSS MARK: a red cross.
    private static let failed = "❌"

    /// U+1F535 LARGE BLUE CIRCLE: the step running right now.
    private static let running = "🔵"

    /// U+26AA MEDIUM WHITE CIRCLE: a step not yet reached.
    private static let waiting = "⚪"

    /// Thin space between markers, so five of them read as a row rather
    /// than one blob.
    private static let markerGap = " "

    /// The meter and its sentence, for the sheet.
    ///
    /// `activity` is what is happening now, in the holder's terms. It
    /// goes under the markers because the markers say where in the run
    /// this is and the sentence says what to do about it -- which is
    /// almost always to keep holding.
    internal static func line(
      states: [CardPrimingStep: CardPrimingStep.State],
      activity: String
    ) -> String {
      let meter =
        CardPrimingStep.allCases
        .map { Self.marker(states[$0] ?? .waiting) }
        .joined(separator: Self.markerGap)
      return meter + "\n" + activity
    }

    /// The marker one step's state is drawn as.
    private static func marker(_ state: CardPrimingStep.State) -> String {
      switch state {
      case .done:
        Self.done
      case .failed:
        Self.failed
      case .running:
        Self.running
      case .waiting:
        Self.waiting
      }
    }
  }

#endif
