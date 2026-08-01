#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import SwiftUI

  /// What the Safari setup action needs, and the one thing it can do.
  ///
  /// The model holds no secret. It reads the card access number through
  /// ``CardCredentialStore``, which never hands the digits back. Apple's
  /// NFC sheets report the operation; the setup form retains no progress
  /// or result presentation of its own.
  @available(iOS 26.0, *)
  @MainActor
  @Observable
  internal final class CardPrimingModel {
    /// Result retained only for device automation.
    internal enum RunResult: Equatable {
      case notRun
      case succeeded
      case failed
    }

    /// What the device currently holds, so the screen can say whether
    /// priming is even possible.
    internal private(set) var contents = CardCredentialStore.contents()

    /// Whether this device offers the phone's own antenna.
    ///
    /// Reader selection is automatic: an available transport is always
    /// usable and there is no holder preference that can disable it.
    internal private(set) var allowsNearField = SupportedCardTransports.offersNearField

    /// True while a hold is in progress.
    internal private(set) var isRunning = false

    /// The last run's testable result, deliberately not rendered in the setup form.
    ///
    /// Apple's NFC sheet reports it to the holder.
    internal private(set) var lastRunResult = RunResult.notRun

    /// Refreshes what is stored, without touching any secret.
    internal func refresh() {
      contents = CardCredentialStore.contents()
      allowsNearField = SupportedCardTransports.offersNearField
    }

    /// Primes the card for later system-driven logins.
    internal func prime() async {
      guard !isRunning else { return }
      refresh()
      guard contents.hasCardAccessNumber, allowsNearField else { return }
      isRunning = true
      lastRunResult = .notRun
      // The tick runs for the whole hold. It is what makes the outcome
      // legible: it stops, and the tone that replaces it is the answer.
      CardPrimingFeedback.startWorking()
      let outcome = await CardPriming.prime(
        progress: { _ in
          // The meter on the system NFC sheet carries progress; the
          // holder is looking at the card, not at this screen.
        },
        step: { _, _ in
          // The sheet draws the steps. See `PrimingSheetReporter`.
        })
      let succeeded = outcome.stored && outcome.registered
      if outcome.cancelled {
        // A holder who closed the sheet knows what they did. Stop the
        // sound; do not answer them with a failure tone.
        lastRunResult = .notRun
        CardPrimingFeedback.stopWorking()
      } else {
        lastRunResult = succeeded ? .succeeded : .failed
        CardPrimingFeedback.report(succeeded: succeeded)
      }
      refresh()
      isRunning = false
    }
  }

#endif
