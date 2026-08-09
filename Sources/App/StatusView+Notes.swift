#if os(macOS)

  import CardCore
  import Foundation

  /// The two questions the window asks about text rather than about the
  /// card: what to say while it is busy, and whether an entry could yet
  /// be a PIN.
  ///
  /// Neither reads the window's own state, so both live here and leave
  /// the view itself to the parts that do.
  extension StatusView {
    /// The signature style every dropped document can take.
    ///
    /// A container suits any file; a PAdES signature suits only a PDF.
    /// So a batch takes PAdES when every document is a PDF, and a
    /// container otherwise.
    internal static func sharedFormat(for urls: [URL]) -> SignatureFormat {
      let everyOneAPdf = urls.allSatisfy { url in
        SignatureFormat.available(for: url).contains(.pades)
      }
      return everyOneAPdf ? .pades : .asice
    }

    /// What the card is busy with, or nothing when it is not.
    ///
    /// Both notes live on the action row rather than in boxes of
    /// their own: that row is already there and half empty, and a
    /// section that appears and disappears steps the window every
    /// time the card is touched.
    internal static func progressNote(_ signing: SignDocumentModel) -> String? {
      if signing.working {
        return String(localized: "Signing: card, timestamp, revocation data…")
      }
      if signing.readingStamp {
        return String(localized: "Reading the card…")
      }
      return nil
    }

    /// Whether an entry could be a PIN2 at all.
    internal static func isEntryComplete(_ entry: String) -> Bool {
      (Pin2.minimumDigitCount...Pin2.maximumDigitCount).contains(entry.count)
    }
  }

#endif
