// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

extension CardMaintenance {
  internal typealias ActivationNeeds = CardActivationNeeds

  internal struct ActivationReport: Equatable, Sendable {
    internal let scheme: ActivationScheme
    internal let pin1: Outcome
    internal let pin2: Outcome?
  }

  internal struct ActivationExecution: Equatable, Sendable {
    internal let activation: ActivationReport
    internal let snapshot: Snapshot
  }

  internal struct ActivationRequest: Sendable {
    internal let entry: String
    internal let newPin1: String?
    internal let newPin2: String?
  }

  internal static func activate(
    request: ActivationRequest,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> ActivationExecution? {
    await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      message: String(localized: "Hold the card still while it is activated.")
    ) { operations -> ActivationExecution? in
      guard
        let activation = runActivation(
          operations,
          entry: request.entry,
          newPin1: request.newPin1,
          newPin2: request.newPin2
        )
      else {
        return nil
      }
      return ActivationExecution(
        activation: activation,
        snapshot: snapshot(on: operations)
      )
    }
    .flatMap(\.self)
  }

  private static func runActivation(
    _ operations: CardOperations,
    entry: String,
    newPin1: String?,
    newPin2: String?
  ) -> ActivationReport? {
    guard let scheme = classifyScheme(operations) else { return nil }
    guard entry.count == scheme.activationEntryDigitCount else {
      return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
    }
    let needs = operations.activationNeeds(scheme: scheme)
    guard needs.any else {
      return ActivationReport(scheme: scheme, pin1: .alreadyActivated, pin2: nil)
    }
    if needs.pin1, newPin1.flatMap({ Pin1(digits: $0) }) == nil {
      return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
    }
    if needs.pin2, newPin2.flatMap({ Pin2(digits: $0) }) == nil {
      return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
    }
    if let refusal = floorRefusal(operations, scheme: scheme, needs: needs) {
      return ActivationReport(scheme: scheme, pin1: refusal, pin2: nil)
    }

    var first: Outcome = .alreadyActivated
    if needs.pin1, let fresh = newPin1 {
      first = activationStep(
        operations,
        scheme: scheme,
        entry: entry,
        newPin1: fresh
      )
      guard first == .success else {
        return ActivationReport(scheme: scheme, pin1: first, pin2: nil)
      }
    }

    var second: Outcome? = .alreadyActivated
    if needs.pin2, let fresh = newPin2 {
      second = activationStep(
        operations,
        scheme: scheme,
        entry: entry,
        newPin2: fresh
      )
    }
    return ActivationReport(scheme: scheme, pin1: first, pin2: second)
  }

  private static func floorRefusal(
    _ operations: CardOperations,
    scheme: ActivationScheme,
    needs: ActivationNeeds
  ) -> Outcome? {
    let roles: [CredentialRole] =
      switch scheme {
      case .activationCodeIsPuk:
        [.puk]
      case .presetActivationPin:
        [needs.pin1 ? .pin1 : nil, needs.pin2 ? .pin2 : nil].compactMap(\.self)
      }
    for role in roles {
      guard let probe = try? operations.probeRetryCounter(role: role) else {
        return .floorRefused(.refuseUnreadable)
      }
      let verdict = RetryFloor.evaluate(probeOutcome: probe)
      guard verdict == .proceed else {
        return .floorRefused(verdict)
      }
    }
    return nil
  }

  private static func activationStep(
    _ operations: CardOperations,
    scheme: ActivationScheme,
    entry: String,
    newPin1: String
  ) -> Outcome {
    switch scheme {
    case .activationCodeIsPuk:
      guard let code = Puk(digits: entry), let pin = Pin1(digits: newPin1) else {
        return .invalidEntry
      }
      do {
        try operations.unblockPin1(
          puk: code.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    case .presetActivationPin:
      guard let preset = Pin1(digits: entry), let pin = Pin1(digits: newPin1) else {
        return .invalidEntry
      }
      do {
        try operations.changePin1(
          current: preset.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  private static func activationStep(
    _ operations: CardOperations,
    scheme: ActivationScheme,
    entry: String,
    newPin2: String
  ) -> Outcome {
    switch scheme {
    case .activationCodeIsPuk:
      guard let code = Puk(digits: entry), let pin = Pin2(digits: newPin2) else {
        return .invalidEntry
      }
      do {
        try operations.unblockPin2(
          puk: code.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    case .presetActivationPin:
      guard let preset = Pin2(digits: entry), let pin = Pin2(digits: newPin2) else {
        return .invalidEntry
      }
      do {
        try operations.changePin2(
          current: preset.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  internal static func classifyScheme(
    _ operations: CardOperations
  ) -> ActivationScheme? {
    guard let der = try? operations.readCertificate(.authentication) else {
      return nil
    }
    return ActivationScheme.classify(authenticationCertificateDER: der)
  }
}
