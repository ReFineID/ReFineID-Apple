#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import SwiftUI

  /// What the priming screen knows, and the one thing it can do.
  ///
  /// The model holds no secret. It reads the card access number through
  /// ``CardCredentialStore``, which never hands the digits back, and it
  /// opens the signing window through the same type, so the PIN1 digits
  /// are never in this process's own variables either. What it keeps is a
  /// list of sentences the holder can read while they hold the card.
  @available(iOS 26.0, *)
  @MainActor
  @Observable
  internal final class CardPrimingModel {
    /// Why the holder is being asked to confirm before the hold starts.
    ///
    /// Names what the confirmation buys rather than what it protects: the
    /// holder is agreeing to let websites use this card for a while, not
    /// approving an abstract keychain read.
    private static let signingWindowReason = String(
      localized: "Confirm it is you before websites may use this card.")

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

    /// Primes the card, after opening a signing window when PIN1 is
    /// stored.
    ///
    /// The Face ID prompt is deliberately answered BEFORE the card hold
    /// starts: a system authentication sheet competing with the NFC sheet
    /// costs the holder the hold they were in the middle of.
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
      await openSigningWindow()
      outcome = await CardPriming.prime { line in
        Task { @MainActor in
          self.note(line)
        }
      }
      refresh()
      isRunning = false
    }

    /// Opens the fifteen-minute signing window when this device keeps
    /// PIN1, so the logins that follow do not stall on a PIN nobody can
    /// type.
    ///
    /// The holder is asked to confirm first. This is the step that lets
    /// the token extension sign later with nobody present, so it is the
    /// one step here worth a prompt; a refusal is not a failure, it just
    /// leaves every website asking for PIN1 itself.
    private func openSigningWindow() async {
      guard contents.hasPin1 else { return }
      do {
        try await CardCredentialGate.authenticate(reason: Self.signingWindowReason)
      } catch {
        note(String(localized: "Not confirmed. Websites will ask for PIN1 themselves."))
        return
      }
      guard CardCredentialStore.openSigningWindow() else {
        note(String(localized: "The stored PIN1 could not be used. Websites will ask for it."))
        return
      }
      note(
        String(
          localized: "Signing is open for fifteen minutes; it closes on its own when unused."))
    }

    /// Records one line of progress.
    private func note(_ line: String) {
      notes.append(line)
    }
  }

#endif
