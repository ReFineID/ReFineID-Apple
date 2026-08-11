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
      if let failure = error as? Failure {
        return Self.summary(for: failure)
      }
      if let failure = error as? NearFieldCardSession.Failure {
        return Self.summary(for: failure)
      }
      return String(localized: "The card could not be read. Hold it still and try again.")
    }

    /// Explains an app-level priming failure.
    private static func summary(for failure: Failure) -> String {
      switch failure {
      case Failure.cardAccessNumberMissing:
        String(localized: "Store the card access number first, then try again.")
      case Failure.certificateUnreadable:
        String(localized: "The card did not return a usable certificate.")
      case Failure.primeNotStored:
        String(localized: "The card details could not be stored on this iPhone.")
      case Failure.unidentifiedCard:
        String(localized: "The card was not recognized. Try holding it again.")
      }
    }

    /// Explains a CryptoTokenKit registration-field failure.
    private static func summary(for failure: NearFieldCardSession.Failure) -> String {
      switch failure {
      case .antennaBusy:
        String(localized: "The phone's card reader is busy. Try again in a moment.")
      case .cardNeverArrived:
        String(localized: "No card was found. Hold the card against the top of the phone.")
      case .slotRefused:
        String(localized: "This iPhone would not open a card reading session.")
      case .dismissed:
        String(localized: "Setup was cancelled.")
      }
    }
  }

#endif
