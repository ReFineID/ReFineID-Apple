#if DEBUG

  import CardCore
  import CryptoTokenKit
  import Foundation
  import SwiftUI

  /// The window a scene-bound debug mode runs in.
  ///
  /// Two of the modes cannot run the way the rest do. CoreNFC will not open
  /// a slot for a process with no foreground window, and the biometric
  /// prompt that guards the stored PIN1 has nothing to present over, so
  /// running either in the app initializer gets a refusal that looks
  /// exactly like a broken card path. This view exists only to be on screen
  /// while the work runs: it prints to stdout as it goes and exits the
  /// process when the work is done, so
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
    /// The mode this window was opened to run.
    internal let mode: DebugLaunchMode

    internal var body: some View {
      VStack {
        ProgressView()
        Text(verbatim: "ReFineID debug: " + mode.rawValue)
      }
      .padding()
      .task { await Self.run(mode) }
    }

    /// Runs the mode and ends the process with its status.
    private static func run(_ mode: DebugLaunchMode) async {
      switch mode {
      case .ctkSignProbe:
        let report = await Self.offMainThread(CtkSignProbe.report)
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)
      case .openSigningWindow:
        DebugConsole.finish(succeeded: await Self.openSigningWindow())
      case .prime:
        DebugConsole.finish(succeeded: await Self.prime())
      case .diagnostics, .resetCardState, .setCan, .setPin1, .signProbe,
        .tokenPublishProbe, .trace:
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

    /// Opens the fifteen-minute signing window from the stored PIN1.
    ///
    /// The read is gated by the holder's biometrics and blocks inside the
    /// Security framework until they answer, so it is dispatched off the
    /// cooperative pool -- a blocked cooperative thread is how a run that
    /// should have shown a prompt instead shows nothing.
    private static func openSigningWindow() async -> Bool {
      DebugConsole.emit("=== open signing window ===")
      DebugConsole.emit("pin1 stored: \(CardCredentialStore.contents().hasPin1)")
      let opened = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: CardCredentialStore.openSigningWindow())
        }
      }
      DebugConsole.emit("open: \(opened)")
      DebugConsole.emit("signing window open: \(Pin1SigningWindow.isOpen())")
      DebugConsole.emit("=== end ===")
      return opened
    }

    /// Runs the card priming flow with no interface but the system sheet.
    ///
    /// Succeeds only when the card was registered. Priming that stores the
    /// card details and then fails to register leaves a device that looks
    /// set up and cannot log in, which is precisely the failure this mode
    /// exists to catch, so it exits non-zero.
    private static func prime() async -> Bool {
      DebugConsole.emit("=== prime ===")
      #if canImport(CoreNFC) && os(iOS)
        let contents = CardCredentialStore.contents()
        DebugConsole.emit("card access number stored: \(contents.hasCardAccessNumber)")
        DebugConsole.emit("near field permitted: \(CardTransportStore.load().permits(.nearField))")
        let outcome = await CardPriming.prime { line in
          DebugConsole.emit("progress: " + line)
        }
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
