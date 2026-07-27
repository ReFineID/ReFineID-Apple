#if canImport(CoreNFC) && os(iOS)

  import Foundation

  /// How a failed hold is explained, on the sheet and afterwards.
  extension CardPriming {
    /// What the NFC sheet says when a hold fails.
    ///
    /// The sheet is the only surface a holder can see while a card is
    /// against the phone, so it carries the reason rather than a shrug.
    /// While the contactless path is still being brought up it also
    /// carries the underlying error, because "could not read the card"
    /// describes a dozen different faults identically and the difference
    /// is the whole diagnosis. It never names a PIN, a card access
    /// number or the holder: card errors carry status words and typed
    /// reasons, not secrets.
    internal static func sheetMessage(for error: any Error) -> String {
      let reason = Self.summary(for: error)
      #if DEBUG
        return reason + " (" + String(describing: error) + ")"
      #else
        return reason
      #endif
    }

    internal static func summary(for error: any Error) -> String {
      switch error {
      case Failure.cardAccessNumberMissing:
        String(localized: "Store the card access number first, then try again.")
      case Failure.certificateUnreadable:
        String(localized: "The card did not return a usable certificate.")
      case Failure.primeNotStored:
        String(localized: "The card details could not be stored on this iPhone.")
      case Failure.unidentifiedCard:
        String(localized: "The card was not recognized. Try holding it again.")
      case NearFieldCardSession.Failure.antennaBusy:
        String(localized: "The phone's card reader is busy. Try again in a moment.")
      case NearFieldCardSession.Failure.cardNeverArrived:
        String(localized: "No card was found. Hold the card against the top of the phone.")
      case NearFieldCardSession.Failure.slotRefused:
        String(localized: "This iPhone would not open a card reading session.")
      default:
        String(localized: "The card could not be read. Hold it still and try again.")
      }
    }
  }

#endif
