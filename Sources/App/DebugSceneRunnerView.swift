// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import CryptoTokenKit
  import Foundation
  import SwiftUI

  /// The window a scene-bound debug mode runs in.
  ///
  /// Two modes cannot run the way the rest do. CoreNFC will not open a
  /// slot for a process with no foreground window, and the system PIN
  /// sheet needs a live run loop. Running either in the app initializer
  /// gets a refusal that looks exactly like a broken card path. This view
  /// exists only to be on screen while the work runs: it prints to stdout
  /// as it goes and exits the process when the work is done, so
  /// `xcrun devicectl device process launch --console` still sees a run
  /// that starts, narrates itself, and ends with a status.
  ///
  /// Progress is printed line by line rather than collected, because both
  /// modes block on a system sheet the holder has to answer. A run that
  /// printed only at the end would say nothing at all about the hold that
  /// never completed.
  ///
  /// DEBUG only.
  ///
  /// Provenance: the auto-starting `SafariIdentityPrimeView` used by
  /// `--prime-safari --prime-auto` in the donor
  /// `platform/apple/RefineID/Local/SafariIdentityPrimeView.swift`.
  internal struct DebugSceneRunnerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasStarted = false

    /// The mode this window was opened to run.
    internal let mode: DebugLaunchMode

    internal var body: some View {
      VStack {
        if mode == .activationProbe, !hasStarted {
          Button("Start read-only activation probe") {
            hasStarted = true
            Task { await Self.run(mode) }
          }
          .buttonStyle(.borderedProminent)
          .accessibilityHint("Reads card activation state without changing the card")
        } else {
          ProgressView()
        }
        Text(verbatim: "ReFineID debug: " + mode.rawValue)
      }
      .padding()
      .task(id: scenePhase) {
        guard mode != .activationProbe, scenePhase == .active, !hasStarted else { return }
        hasStarted = true
        await Self.run(mode)
      }
    }

    /// Runs the mode and ends the process with its status.
    private static func run(_ mode: DebugLaunchMode) async {
      switch mode {
      case .activationProbe:
        #if REFINEID_LOCAL_CARD && os(iOS)
          let report = await CardMaintenance.debugActivationSignals()
          DebugConsole.emit(report.lines)
          DebugConsole.finish(succeeded: report.succeeded)
        #else
          DebugConsole.emit("activation-probe: NFC is unavailable on macOS")
          DebugConsole.finish(succeeded: false)
        #endif
      case .ctkSignProbe:
        let report = await Self.offMainThread(CtkSignProbe.report)
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)
      case .managementProbe:
        DebugConsole.finish(succeeded: await DebugCardManagementProbe.run())
      case .remoteIdentityProbe:
        let report = DebugRemoteIdentityProbe.report()
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)
      case .prime:
        DebugConsole.finish(succeeded: await Self.prime())
      case .diagnostics, .forgetCan, .paceCheck,
        .resetCardState, .setCan,
        .setPin1, .signDocument, .signProbe, .tokenPublishProbe, .trace:
        DebugConsole.emit(mode.rawValue + ": runs before the window opens, not here")
        DebugConsole.finish(succeeded: false)
      }
    }

    /// Runs blocking work off the main thread and waits for it there.
    ///
    /// The signature the extension services blocks inside the Security
    /// framework until the system PIN sheet has been answered. On the main
    /// thread it would block the run loop that has to present that sheet,
    /// so the sheet never appears and the probe reports a refusal nobody
    /// was offered the chance to satisfy.
    private static func offMainThread(
      _ work: @escaping @Sendable () -> DebugModeReport
    ) async -> DebugModeReport {
      await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: work())
        }
      }
    }

    /// Runs the card priming flow with no interface but the system sheet.
    ///
    /// Succeeds only when the card was registered. Priming that stores the
    /// card details and then fails to register leaves a device that looks
    /// set up and cannot log in, which is precisely the failure this mode
    /// exists to catch, so it exits non-zero.
    private static func prime() async -> Bool {
      DebugConsole.emit("=== prime ===")
      #if REFINEID_LOCAL_CARD && os(iOS)
        let contents = CardCredentialStore.contents()
        DebugConsole.emit("card access number stored: \(contents.hasCardAccessNumber)")
        DebugConsole.emit(
          "near field available: \(SupportedCardTransports.offersNearField)")
        guard let pin1 = ProcessInfo.processInfo.environment["REFINEID_DEBUG_PIN1"],
          !pin1.isEmpty
        else {
          DebugConsole.emit("prime: REFINEID_DEBUG_PIN1 is required")
          return false
        }
        guard #available(iOS 26.0, *) else {
          DebugConsole.emit("prime: the system card slot needs iOS 26")
          DebugConsole.emit("=== end ===")
          return false
        }
        guard let storedAccessNumber = CardCredentialStore.displayedCardAccessNumber() else {
          DebugConsole.emit("prime: a stored card access number is required")
          DebugConsole.emit("=== end ===")
          return false
        }
        let outcome = await CardPriming.prime(
          cardAccessNumber: storedAccessNumber,
          pin1: pin1,
          progress: { line in
            DebugConsole.emit("progress: " + line)
          },
          step: { step, state in
            DebugConsole.emit("step: \(step) \(state)")
          })
        DebugConsole.emit("stored: \(outcome.stored)")
        DebugConsole.emit("registered: \(outcome.registered)")
        DebugConsole.emit("summary: " + outcome.summary)
        DebugConsole.emit("primed cards now: \(PrimeStore.storedCount())")
        DebugConsole.emit(
          "registered smart cards now: "
            + "\(TKSmartCardTokenRegistrationManager.default.registeredSmartCardTokens.count)")
        DebugConsole.emit("=== end ===")
        return outcome.registered
      #else
        DebugConsole.emit("this platform has no near-field antenna to prime over")
        DebugConsole.emit("=== end ===")
        return false
      #endif
    }
  }

#endif
