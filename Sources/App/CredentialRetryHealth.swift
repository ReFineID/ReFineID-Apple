// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Observation
import SwiftUI

/// Session-only presentation of one complete, side-effect-free retry probe.
///
/// No counter is persisted. Card management publishes reports it already
/// needed; reader insertion may also start one narrow, cancellable counter
/// probe. There is no polling, and identity presentation never waits for it.
@MainActor
@Observable
internal final class CredentialRetryHealth {
  internal enum Level: Equatable {
    case pristine
    case warning
    case critical

    fileprivate var color: Color {
      switch self {
      case .pristine: .green
      case .warning: .yellow
      case .critical: .red
      }
    }

    fileprivate var badge: String {
      switch self {
      case .pristine: "checkmark.circle.fill"
      case .warning: "exclamationmark.triangle.fill"
      case .critical: "xmark.octagon.fill"
      }
    }

    fileprivate var accessibilityValue: String {
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

  internal private(set) var level: Level?
  internal private(set) var recovery: Recovery?

  /// The accepted report behind the level, so the management screen
  /// can name the exact counters the color came from.
  internal private(set) var report: CredentialProbeReport?

  @ObservationIgnored private var readerRefresh: Task<Void, Never>?
  @ObservationIgnored private var refreshGeneration = 0

  private init() {}

  /// Starts one non-blocking retry probe for the newly inserted reader card.
  ///
  /// A replacement or removal invalidates the generation, so a late answer can
  /// never color the key for a card that is no longer present.
  internal func refreshFromReader() {
    cancelReaderRefresh()
    level = nil
    report = nil
    let generation = refreshGeneration
    readerRefresh = Task { [weak self] in
      let report = await CardMaintenance.credentialReport(
        transport: .reader,
        cardAccessNumber: nil
      )
      guard
        !Task.isCancelled,
        let self,
        refreshGeneration == generation
      else { return }
      readerRefresh = nil
      apply(report)
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
    if attempts.contains(where: { $0 <= 2 }) {
      if puk == 0 {
        recovery = .unrecoverable
      } else if puk <= 2 {
        recovery = .useOtherSoftware
      } else if pin1 <= 2 {
        recovery = .resetPin1
      } else if pin2 <= 2 {
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

  private static func attempts(_ outcome: RetryProbeOutcome) -> UInt8? {
    switch outcome {
    case .remaining(let count): count.attemptsRemaining
    case .locked: 0
    case .invalidated, .noInformation, .other, .verified: nil
    }
  }
}

/// The common key artwork for every route into PIN management.
///
/// Tint is reinforced by a differently shaped system badge and a VoiceOver
/// value, so health is never communicated by color alone.
internal struct CredentialRetryHealthKey: View {
  internal let level: CredentialRetryHealth.Level?
  internal let systemName: String

  /// Whether the route this key opens can be taken right now.
  ///
  /// An unprobed key on an open route is green -- no known issue --
  /// while a closed route greys out like its row.
  internal let routeAvailable: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animationTrigger = false

  internal init(
    level: CredentialRetryHealth.Level?,
    systemName: String = "key",
    routeAvailable: Bool = true
  ) {
    self.level = level
    self.systemName = systemName
    self.routeAvailable = routeAvailable
  }

  internal var body: some View {
    ZStack(alignment: .bottomTrailing) {
      if let level = displayedLevel {
        Image(systemName: systemName)
          .contentTransition(
            .symbolEffect(
              .replace.magic(fallback: .offUp.byLayer),
              options: .nonRepeating)
          )
          .foregroundStyle(level.color)
        statusBadge(level)
      } else {
        Image(systemName: systemName)
          .contentTransition(
            .symbolEffect(
              .replace.magic(fallback: .offUp.byLayer),
              options: .nonRepeating)
          )
          .foregroundStyle(
            routeAvailable
              ? AnyShapeStyle(.green)
              : AnyShapeStyle(.secondary))
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Change or Reset PINs"))
    .accessibilityValue(
      displayedLevel?.accessibilityValue
        ?? String(localized: "Credential retry status unavailable")
    )
    .onAppear { animateIfNeeded(displayedLevel) }
    .onChange(of: displayedLevel) { _, newLevel in
      animateIfNeeded(newLevel)
    }
  }

  /// A closed route never wears a cached health level.
  ///
  /// The keys grey out with their row until the card is verified
  /// again, whatever the last report said.
  private var displayedLevel: CredentialRetryHealth.Level? {
    routeAvailable ? level : nil
  }

  @ViewBuilder private func statusBadge(
    _ level: CredentialRetryHealth.Level
  ) -> some View {
    switch level {
    case .pristine:
      badge(level)
    case .warning:
      badge(level)
        .symbolEffect(.pulse, value: animationTrigger)
    case .critical:
      badge(level)
        .symbolEffect(.bounce, options: .repeating, value: animationTrigger)
    }
  }

  private func badge(_ level: CredentialRetryHealth.Level) -> some View {
    Image(systemName: level.badge)
      .font(.system(size: 8, weight: .bold))
      .foregroundStyle(level.color)
      .background(.background, in: Circle())
  }

  /// Motion calls attention only to degraded states.
  ///
  /// Yielding one render pass lets an initially degraded badge exist
  /// before its effect begins. Yellow pulses once; red repeats until the
  /// state changes. There is no timing constant, and Reduce Motion
  /// suppresses both. UI automation also opts out: XCTest waits for
  /// animation quiescence before taps, while the red state intentionally
  /// never becomes quiescent for a holder.
  private func animateIfNeeded(_ level: CredentialRetryHealth.Level?) {
    guard
      !reduceMotion,
      !Self.uiAutomationDisablesMotion,
      level == .warning || level == .critical
    else { return }
    Task { @MainActor in
      await Task.yield()
      animationTrigger.toggle()
    }
  }

  private static var uiAutomationDisablesMotion: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--ui-test-disable-motion")
    #else
      false
    #endif
  }
}
