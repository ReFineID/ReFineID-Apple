// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// Session-only presentation of one complete, side-effect-free retry probe.
///
/// No counter is persisted. Card management publishes reports it already
/// needed; reader insertion may also start one narrow, cancellable counter
/// probe. There is no polling, and identity presentation never waits for it.
@MainActor
internal final class CredentialRetryHealth: ObservableObject {
  internal enum Level: Equatable {
    case pristine
    case warning
    case critical

    internal var color: Color {
      switch self {
      case .pristine:
        .green
      case .warning:
        .yellow
      case .critical:
        .red
      }
    }

    internal var badge: String {
      switch self {
      case .pristine:
        "checkmark.circle.fill"
      case .warning:
        "exclamationmark.triangle.fill"
      case .critical:
        "xmark.octagon.fill"
      }
    }

    internal var accessibilityValue: String {
      switch self {
      case .pristine:
        String(localized: "All credential attempts are available")
      case .warning:
        String(localized: "A credential has fewer than five attempts remaining")
      case .critical:
        String(localized: "A credential is blocked or has at most two attempts remaining")
      }
    }
  }

  /// The only useful destination while the key is critical.
  ///
  /// PIN 1 wins when both PINs need recovery. A low PUK removes every
  /// operation because both reset commands spend that counter.
  internal enum Recovery: Equatable {
    case resetPin1
    case resetPin2
    case useOtherSoftware
    case unrecoverable
  }

  internal static let shared = CredentialRetryHealth()

  @Published internal private(set) var level: Level?
  @Published internal private(set) var recovery: Recovery?

  /// The accepted report behind the level, so the management screen
  /// can name the exact counters the color came from.
  @Published internal private(set) var report: CredentialProbeReport?

  private var readerRefresh: Task<Void, Never>?
  private var refreshGeneration = 0

  private init() {
    // The one instance is `shared`; nothing is set up per instance.
  }

  /// Starts one non-blocking retry probe for the newly inserted reader card.
  ///
  /// A replacement or removal invalidates the generation, so a late answer can
  /// never color the key for a card that is no longer present.
  private static func attempts(_ outcome: RetryProbeOutcome) -> UInt8? {
    switch outcome {
    case .remaining(let count):
      count.attemptsRemaining
    case .locked:
      0
    case .invalidated, .noInformation, .other, .verified:
      nil
    }
  }

  internal func refreshFromReader() {
    cancelReaderRefresh()
    level = nil
    report = nil
    let generation = refreshGeneration
    readerRefresh = Task { [weak self] in
      let probed = await CardMaintenance.credentialReport(
        transport: .reader,
        cardAccessNumber: nil
      )
      guard
        !Task.isCancelled,
        let self,
        refreshGeneration == generation
      else { return }
      readerRefresh = nil
      apply(probed)
    }
  }

  /// Accepts only a complete and plausible report.
  ///
  /// A locked result is the card's semantic zero; every other non-counter
  /// outcome makes the status unavailable rather than inviting a guess.
  internal func update(_ report: CredentialProbeReport?) {
    cancelReaderRefresh()
    apply(report)
  }

  private func apply(_ report: CredentialProbeReport?) {
    guard let report,
      let pin1 = Self.attempts(report.pin1),
      let pin2 = Self.attempts(report.pin2),
      let puk = Self.attempts(report.puk)
    else {
      recovery = nil
      level = nil
      self.report = nil
      return
    }

    let attempts = [pin1, pin2, puk]
    guard attempts.allSatisfy({ $0 <= RetryCount.pristineAllowance }) else {
      recovery = nil
      level = nil
      self.report = nil
      return
    }
    self.report = report
    if attempts.contains(where: { $0 <= RetryCount.lowAttemptCeiling }) {
      if puk == 0 {
        recovery = .unrecoverable
      } else if puk <= RetryCount.lowAttemptCeiling {
        recovery = .useOtherSoftware
      } else if pin1 <= RetryCount.lowAttemptCeiling {
        recovery = .resetPin1
      } else if pin2 <= RetryCount.lowAttemptCeiling {
        recovery = .resetPin2
      } else {
        recovery = nil
      }
      level = .critical
    } else if attempts.allSatisfy({ $0 == RetryCount.pristineAllowance }) {
      recovery = nil
      level = .pristine
    } else {
      recovery = nil
      level = .warning
    }
  }

  internal func clear() {
    cancelReaderRefresh()
    recovery = nil
    level = nil
    report = nil
  }

  private func cancelReaderRefresh() {
    refreshGeneration &+= 1
    readerRefresh?.cancel()
    readerRefresh = nil
  }

}
