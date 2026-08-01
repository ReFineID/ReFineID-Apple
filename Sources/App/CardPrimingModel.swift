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

    /// How far the last or running hold got, step by step.
    ///
    /// The system NFC sheet cannot report this. It has no failure state
    /// at all -- `TKSmartCardSlotNFCSession` offers only a message and
    /// `endSession`, so it dismisses with the same checkmark whether the
    /// hold worked or broke at PACE. This is where a holder finds out
    /// which it was.
    internal private(set) var steps: [CardPrimingStep: CardPrimingStep.State] = [:]

    /// The sentence the last hold ended with, for the holder to read.
    internal private(set) var summary: String?

    /// How one step is going, for the view that draws it.
    internal func state(of step: CardPrimingStep) -> CardPrimingStep.State {
      steps[step] ?? .waiting
    }

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
      summary = nil
      steps = [:]
      let outcome = await CardPriming.prime(
        progress: { _ in
          // The step rows carry progress; the text is for diagnostics.
        },
        step: { [weak self] step, state in
          Task { @MainActor in
            self?.steps[step] = state
          }
        })
      let succeeded = outcome.stored && outcome.registered
      lastRunResult = succeeded ? .succeeded : .failed
      summary = outcome.summary
      CardPrimingFeedback.report(succeeded: succeeded)
      refresh()
      isRunning = false
    }
  }

#endif
