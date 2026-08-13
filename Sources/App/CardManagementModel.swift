// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Observation

@MainActor
@Observable
internal final class CardManagementModel {
  internal private(set) var report: CredentialProbeReport?
  internal private(set) var activationNeeds = CardMaintenance.ActivationNeeds(
    pin1: true,
    pin2: true
  )
  internal private(set) var offersActivation = false
  internal private(set) var working = false
  internal private(set) var failure: String?
  internal private(set) var notice: String?

  internal var transport: CardMaintenance.Transport {
    didSet {
      guard transport != oldValue else { return }
      report = nil
      offersActivation = false
      failure = nil
      notice = nil
    }
  }

  internal var cardAccessNumber: String
  internal let availableTransports = CardMaintenance.availableTransports

  internal var canContactCard: Bool {
    transport == .reader
      || cardAccessNumber.count == CardAccessNumber.digitCount
  }

  private var offeredCardAccessNumber: String? {
    transport == .nearField ? cardAccessNumber : nil
  }

  private var unreadableCardMessage: String {
    transport == .nearField
      ? "The card could not be read over NFC. Check its card access number and try again."
      : "No readable card. Connect a reader and insert the card."
  }

  internal init() {
    transport = CardMaintenance.preferredTransport
    cardAccessNumber = CardCredentialStore.displayedCardAccessNumber() ?? ""
  }

  internal func refresh() async {
    guard !working, canContactCard else { return }
    working = true
    failure = nil
    notice = nil
    let result = await CardMaintenance.snapshot(
      transport: transport,
      cardAccessNumber: offeredCardAccessNumber
    )
    working = false
    guard let result else {
      report = nil
      offersActivation = false
      failure = unreadableCardMessage
      return
    }
    apply(result)
  }

  internal func changePin1(current: String, new: String) async -> Bool {
    await perform(presenting: "PIN 1", accepted: "PIN 1 changed.") {
      await CardMaintenance.changePin1(
        current: current,
        new: new,
        transport: transport,
        cardAccessNumber: offeredCardAccessNumber
      )
    }
  }

  internal func changePin2(current: String, new: String) async -> Bool {
    await perform(presenting: "PIN 2", accepted: "PIN 2 changed.") {
      await CardMaintenance.changePin2(
        current: current,
        new: new,
        transport: transport,
        cardAccessNumber: offeredCardAccessNumber
      )
    }
  }

  internal func unblock(target: CredentialRole, puk: String, new: String) async -> Bool {
    let accepted =
      target == .pin2
      ? "PIN 2 unblocked and set to the new value."
      : "PIN 1 unblocked and set to the new value."
    return await perform(presenting: "PUK", accepted: accepted) {
      if target == .pin2 {
        return await CardMaintenance.unblockPin2(
          puk: puk,
          new: new,
          transport: transport,
          cardAccessNumber: offeredCardAccessNumber
        )
      }
      return await CardMaintenance.unblockPin1(
        puk: puk,
        new: new,
        transport: transport,
        cardAccessNumber: offeredCardAccessNumber
      )
    }
  }

  internal func activate(
    entry: String,
    newPin1: String?,
    newPin2: String?,
    allowReactivation: Bool
  ) async -> Bool {
    guard !working, canContactCard else { return false }
    working = true
    failure = nil
    notice = nil
    let execution = await CardMaintenance.activate(
      request: CardMaintenance.ActivationRequest(
        entry: entry,
        newPin1: newPin1,
        newPin2: newPin2,
        allowReactivation: allowReactivation
      ),
      transport: transport,
      cardAccessNumber: offeredCardAccessNumber
    )
    working = false
    guard let execution else {
      failure = "The card could not be classified for activation."
      return false
    }
    let succeeded = describe(execution.activation)
    apply(execution.snapshot, preservingOutcome: true)
    return succeeded
  }

  private func apply(
    _ snapshot: CardMaintenance.Snapshot,
    preservingOutcome: Bool = false
  ) {
    report = snapshot.report
    if let needs = snapshot.activationNeeds {
      activationNeeds = needs
      offersActivation = needs.any
    } else {
      offersActivation = false
    }
    if !preservingOutcome {
      failure = nil
      notice = nil
    }
  }

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

  private func activationEntryName(_ scheme: ActivationScheme) -> String {
    switch scheme {
    case .activationCodeIsPuk:
      "activation code"
    case .presetActivationPin:
      "activation PIN"
    }
  }

  private func perform(
    presenting: String,
    accepted: String,
    _ operation: () async -> CardMaintenance.MutationReport
  ) async -> Bool {
    guard !working, canContactCard else { return false }
    working = true
    failure = nil
    notice = nil
    let mutation = await operation()
    working = false
    if mutation.outcome == .success {
      notice = accepted
    } else {
      failure = message(for: mutation.outcome, presenting: presenting)
    }
    if let snapshot = mutation.snapshot {
      apply(snapshot, preservingOutcome: true)
    }
    return mutation.outcome == .success
  }

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
      unreadableCardMessage
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
