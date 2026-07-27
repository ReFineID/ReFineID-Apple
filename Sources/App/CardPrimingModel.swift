#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import SwiftUI

  /// What the priming screen knows, and the one thing it can do.
  ///
  /// The model holds no secret. It reads the card access number through
  /// ``CardCredentialStore``, which never hands the digits back. What it
  /// keeps is a list of sentences the holder can read while they hold the
  /// card.
  @available(iOS 26.0, *)
  @MainActor
  @Observable
  internal final class CardPrimingModel {
    /// What the device currently holds, so the screen can say whether
    /// priming is even possible.
    internal private(set) var contents = CardCredentialStore.contents()

    /// Whether the holder currently allows the phone's own antenna.
    ///
    /// Priming is the contactless path and nothing else; a holder who has
    /// switched that transport off is not asked to hold a card.
    internal private(set) var allowsNearField = CardTransportStore.load().permits(.nearField)

    /// What the run has done so far, oldest first.
    internal private(set) var notes: [String] = []

    /// How far the current hold got, one entry per step.
    ///
    /// Kept separate from the notes because a holder pressing a card
    /// against a phone needs to see progress at a glance, not read.
    internal private(set) var steps: [CardPrimingStep: CardPrimingStep.State] = [:]

    /// The finished run, or nil before the first one.
    internal private(set) var outcome: CardPriming.Outcome?

    /// True while a hold is in progress.
    internal private(set) var isRunning = false

    /// Set when the run could not be started at all.
    internal private(set) var failure: String?

    /// Refreshes what is stored, without touching any secret.
    internal func refresh() {
      contents = CardCredentialStore.contents()
      allowsNearField = CardTransportStore.load().permits(.nearField)
    }

    /// Primes the card for later system-driven logins.
    internal func prime() async {
      guard !isRunning else { return }
      refresh()
      guard contents.hasCardAccessNumber else {
        failure = String(
          localized: "Store the card access number first, on the card details screen.")
        return
      }
      guard allowsNearField else {
        failure = String(localized: "Switch \"Use phone as reader\" on before setting up a card.")
        return
      }
      isRunning = true
      notes = []
      outcome = nil
      failure = nil
      steps = [:]
      outcome = await CardPriming.prime(
        progress: { line in
          Task { @MainActor in
            self.note(line)
          }
        },
        step: { step, state in
          Task { @MainActor in
            self.steps[step] = state
          }
        })
      refresh()
      isRunning = false
    }

    /// Records one line of progress.
    private func note(_ line: String) {
      notes.append(line)
    }
  }

#endif
