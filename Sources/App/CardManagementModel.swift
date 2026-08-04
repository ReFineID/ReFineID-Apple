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
      working = false
    }

    /// Changes PIN1; true when the card accepted.
    internal func changePin1(current: String, new: String) async -> Bool {
      await perform(presenting: "PIN1", accepted: "PIN1 changed.") {
        await CardMaintenance.changePin1(current: current, new: new)
      }
    }

    /// Changes PIN2; true when the card accepted.
    internal func changePin2(current: String, new: String) async -> Bool {
      await perform(presenting: "PIN2", accepted: "PIN2 changed.") {
        await CardMaintenance.changePin2(current: current, new: new)
      }
    }

    /// Unblocks a PIN with the PUK; true when the card accepted.
    internal func unblock(target: CredentialRole, puk: String, new: String) async -> Bool {
      let accepted =
        target == .pin2
        ? "PIN2 unblocked and set to the new value."
        : "PIN1 unblocked and set to the new value."
      return await perform(presenting: "PUK", accepted: accepted) {
        target == .pin2
          ? await CardMaintenance.unblockPin2(puk: puk, new: new)
          : await CardMaintenance.unblockPin1(puk: puk, new: new)
      }
    }

    /// Activates the card; true when both PINs were set.
    internal func activate(
      entry: String,
      newPin1: String,
      newPin2: String,
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
        return false
      }
      switch (activation.pin1, activation.pin2) {
      case (.success, .success):
        notice = "Card activated: PIN1 and PIN2 are set."
        await refresh()
        return true
      case (.success, .some(let second)):
        failure = message(for: second, presenting: activationEntryName(activation.scheme))
          .map { "PIN1 was set, but PIN2 was not: \($0)" }
        await refresh()
        return false
      case (.alreadyActivated, _):
        failure =
          "This card looks activated already. Activating again would spend "
          + "a retry; enable reactivation only if you are sure."
        return false
      case (let first, _):
        failure = message(for: first, presenting: activationEntryName(activation.scheme))
        await refresh()
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
        await refresh()
        return true
      }
      failure = message(for: outcome, presenting: presenting)
      if case .rejected = outcome {
        await refresh()
      }
      return false
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
