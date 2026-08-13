// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

extension CardMaintenance {
  internal struct Snapshot: Equatable, Sendable {
    internal let report: CredentialProbeReport?
    internal let activationNeeds: ActivationNeeds?
  }

  internal struct MutationReport: Equatable, Sendable {
    internal let outcome: Outcome
    internal let snapshot: Snapshot?
  }

  internal static func snapshot(
    transport: Transport,
    cardAccessNumber: String?
  ) async -> Snapshot? {
    await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      message: String(localized: "Hold the card near the top of the iPhone.")
    ) { operations in
      snapshot(on: operations)
    }
  }

  internal static func changePin1(
    current: String,
    new: String,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> MutationReport {
    await withFloor(
      .pin1,
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      message: String(localized: "Hold the card still while PIN 1 is changed.")
    ) { operations in
      guard
        let currentPin = Pin1(digits: current),
        let newPin = Pin1(digits: new)
      else {
        return .invalidEntry
      }
      do {
        try operations.changePin1(
          current: currentPin.consumeForSingleTransmission(),
          new: newPin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  internal static func changePin2(
    current: String,
    new: String,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> MutationReport {
    await withFloor(
      .pin2,
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      message: String(localized: "Hold the card still while PIN 2 is changed.")
    ) { operations in
      guard
        let currentPin = Pin2(digits: current),
        let newPin = Pin2(digits: new)
      else {
        return .invalidEntry
      }
      do {
        try operations.changePin2(
          current: currentPin.consumeForSingleTransmission(),
          new: newPin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  internal static func unblockPin1(
    puk: String,
    new: String,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> MutationReport {
    await withFloor(
      .puk,
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      message: String(localized: "Hold the card still while PIN 1 is reset.")
    ) { operations in
      guard let key = Puk(digits: puk), let pin = Pin1(digits: new) else {
        return .invalidEntry
      }
      do {
        try operations.unblockPin1(
          puk: key.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  internal static func unblockPin2(
    puk: String,
    new: String,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> MutationReport {
    await withFloor(
      .puk,
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      message: String(localized: "Hold the card still while PIN 2 is reset.")
    ) { operations in
      guard let key = Puk(digits: puk), let pin = Pin2(digits: new) else {
        return .invalidEntry
      }
      do {
        try operations.unblockPin2(
          puk: key.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  private static func withFloor(
    _ role: CredentialRole,
    transport: Transport,
    cardAccessNumber: String?,
    message: String,
    _ operation: @escaping @Sendable (CardOperations) -> Outcome
  ) async -> MutationReport {
    let result = await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      message: message
    ) { operations -> MutationReport in
      guard let probe = try? operations.probeRetryCounter(role: role) else {
        return MutationReport(
          outcome: .floorRefused(.refuseUnreadable),
          snapshot: snapshot(on: operations)
        )
      }
      let verdict = RetryFloor.evaluate(probeOutcome: probe)
      guard verdict == .proceed else {
        return MutationReport(
          outcome: .floorRefused(verdict),
          snapshot: snapshot(on: operations)
        )
      }
      return MutationReport(
        outcome: operation(operations),
        snapshot: snapshot(on: operations)
      )
    }
    return result ?? MutationReport(outcome: .noCard, snapshot: nil)
  }

  internal static func snapshot(on operations: CardOperations) -> Snapshot {
    let scheme = classifyScheme(operations)
    let needs = scheme.map { activationScheme in
      operations.activationNeeds(scheme: activationScheme)
    }
    let report = try? operations.probeCredentials()
    return Snapshot(report: report, activationNeeds: needs)
  }
}
