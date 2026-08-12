// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Observation

  /// State for the card-management window: the counter-safe retry
  /// reading, one operation in flight at a time, and the outcome as a
  /// sentence.
  ///
  /// Entries pass through as strings and are never kept: the fields own
  /// them until the driver consumes them, and nothing here stores,
  /// logs, or reads back a credential.
  @MainActor
  @Observable
  internal final class CardManagementModel {
    /// The last counter-safe probe of all three credentials.
    internal private(set) var report: CredentialProbeReport?

    /// Which PINs still await their first value.
    ///
    /// Both by default, so a preview with no card to ask shows the
    /// whole form; a reading replaces it with what the card says.
    /// An interrupted activation leaves one PIN set and one waiting,
    /// and the form asks only for the waiting one - setting the other
    /// again would spend a retry on a value that cannot match.
    internal private(set) var activationNeeds = CardMaintenance.ActivationNeeds(
      pin1: true, pin2: true
    )

    /// Whether this card can still be activated.
    ///
    /// False until a reading says otherwise: activation is a one-time
    /// factory state, and offering it for a card already in use can
    /// only spend a retry against a credential the holder replaced.
    internal private(set) var offersActivation = false

    /// Whether an operation (or the probe) is on the card now.
    internal private(set) var working = false

    /// What went wrong, as one user-facing sentence.
    internal private(set) var failure: String?

    /// What succeeded, as one user-facing sentence.
    internal private(set) var notice: String?

    /// Re-reads the retry counters, counter-safe.
    internal func refresh() async {
      guard !working else { return }
      working = true
      report = await CardMaintenance.probeCredentials()
      let needs = await CardMaintenance.activationNeeds()
      if let needs {
        activationNeeds = needs
      }
      offersActivation = needs?.any == true
      working = false
    }

    /// Changes PIN1; true when the card accepted.
    internal func changePin1(current: String, new: String) async -> Bool {
      await perform(presenting: "PIN 1", accepted: "PIN 1 changed.") {
        await CardMaintenance.changePin1(current: current, new: new)
      }
    }

    /// Changes PIN2; true when the card accepted.
    internal func changePin2(current: String, new: String) async -> Bool {
      await perform(presenting: "PIN 2", accepted: "PIN 2 changed.") {
        await CardMaintenance.changePin2(current: current, new: new)
      }
    }

    /// Unblocks a PIN with the PUK; true when the card accepted.
    internal func unblock(target: CredentialRole, puk: String, new: String) async -> Bool {
      let accepted =
        target == .pin2
        ? "PIN 2 unblocked and set to the new value."
        : "PIN 1 unblocked and set to the new value."
      return await perform(presenting: "PUK", accepted: accepted) {
        target == .pin2
          ? await CardMaintenance.unblockPin2(puk: puk, new: new)
          : await CardMaintenance.unblockPin1(puk: puk, new: new)
      }
    }

    /// Activates the card; true when every waiting PIN was set.
    ///
    /// A nil PIN is one the form did not ask for because the card
    /// already carries it; the flow sets only what still waits.
    internal func activate(
      entry: String,
      newPin1: String?,
      newPin2: String?,
      allowReactivation: Bool
    ) async -> Bool {
      guard !working else { return false }
      working = true
      failure = nil
      notice = nil
      let activation = await CardMaintenance.activate(
        entry: entry,
        newPin1: newPin1,
        newPin2: newPin2,
        allowReactivation: allowReactivation
      )
      working = false
      guard let activation else {
        failure = "The card could not be classified for activation."
        await refresh()
        return false
      }
      let succeeded = describe(activation)
      await refresh()
      return succeeded
    }

    /// Turns an activation result into the sentence shown, and says
    /// whether every waiting PIN was set.
    ///
    /// `alreadyActivated` on one PIN beside progress on the other is a
    /// skip, not a refusal: an interrupted activation left that PIN
    /// set, and this run finished the card.
    private func describe(_ activation: CardMaintenance.ActivationReport) -> Bool {
      let entry = activationEntryName(activation.scheme)
      switch (activation.pin1, activation.pin2) {
      case (.success, .success):
        notice = "Card activated: PIN 1 and PIN 2 are set."
        return true
      case (.alreadyActivated, .success):
        notice = "Card activated: PIN 2 is set. PIN 1 already was."
        return true
      case (.success, .alreadyActivated), (.success, nil):
        notice = "Card activated: PIN 1 is set. PIN 2 already was."
        return true
      case (.success, .some(let second)):
        failure = message(for: second, presenting: entry)
          .map { "PIN 1 was set, but PIN 2 was not: \($0)" }
        return false
      case (.alreadyActivated, .some(let second)):
        failure = message(for: second, presenting: entry)
          .map { "PIN 2 was not set: \($0)" }
        return false
      case (.alreadyActivated, nil):
        failure =
          "This card looks activated already. Activating again would spend "
          + "a retry; enable reactivation only if you are sure."
        return false
      case (let first, _):
        failure = message(for: first, presenting: entry)
        return false
      }
    }

    /// What the activation entry is called under a scheme, for
    /// messages.
    private func activationEntryName(_ scheme: ActivationScheme) -> String {
      switch scheme {
      case .activationCodeIsPuk:
        "activation code"
      case .presetActivationPin:
        "activation PIN"
      }
    }

    /// Runs one operation, serialized behind `working`, and turns its
    /// outcome into the failure or notice sentence.
    private func perform(
      presenting: String,
      accepted: String,
      _ operation: () async -> CardMaintenance.Outcome
    ) async -> Bool {
      guard !working else { return false }
      working = true
      failure = nil
      notice = nil
      let outcome = await operation()
      working = false
      if outcome == .success {
        notice = accepted
      } else {
        failure = message(for: outcome, presenting: presenting)
      }
      // Unconditional: the counters are read again after every
      // operation, whatever it answered, because a wrong entry and a
      // newly blocked credential both move them and there is no other
      // way to see it. This is why the window carries no refresh
      // control - the numbers are never stale after an action.
      await refresh()
      return outcome == .success
    }

    /// One sentence per outcome; nil only for success.
    private func message(
      for outcome: CardMaintenance.Outcome,
      presenting: String
    ) -> String? {
      switch outcome {
      case .success:
        nil
      case .invalidEntry:
        "The entry does not fit the credential's digit rules."
      case .noCard:
        "No readable card. Insert the card, or add its CAN first."
      case .floorRefused(.refuseBlocked), .pinBlocked:
        "\(presenting) is blocked."
      case .floorRefused(.refuseLowAttempts):
        "Only one or two attempts remain on \(presenting); ReFineID "
          + "refuses to spend a near-last attempt."
      case .floorRefused:
        "The \(presenting) retry counter could not be read; nothing was sent."
      case .rejected(let remaining):
        "Wrong \(presenting): \(remaining.attemptsRemaining) attempts remain."
      case .invalidated:
        "The credential slot is invalidated; only the issuer can recover it."
      case .alreadyActivated:
        "This card looks activated already."
      case .failed:
        "The card refused the operation."
      }
    }
  }

#endif
