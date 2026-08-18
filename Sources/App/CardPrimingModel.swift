// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import SwiftUI

  /// What the Safari setup action needs, and the one thing it can do.
  ///
  /// The model holds no secret. It reads the card access number through
  /// ``CardCredentialStore``, which never hands the digits back. Apple's
  /// NFC sheet reports the live operation; after it closes, the setup form
  /// retains only a sanitized failure sentence.
  @MainActor
  internal final class CardPrimingModel: ObservableObject {
    /// Result retained only for device automation.
    internal enum RunResult: Equatable {
      case notRun
      case succeeded
      case failed
    }

    /// What the device currently holds, so the screen can say whether
    /// priming is even possible.
    @Published internal private(set) var contents = CardCredentialStore.contents()

    /// Whether this device offers the phone's own antenna.
    ///
    /// Reader selection is automatic: an available transport is always
    /// usable and there is no holder preference that can disable it.
    @Published internal private(set) var allowsNearField = SupportedCardTransports.offersNearField

    /// True while a hold is in progress.
    @Published internal private(set) var isRunning = false

    /// The last run's testable result, deliberately not rendered in the setup form.
    ///
    /// Apple's NFC sheet reports it to the holder.
    @Published internal private(set) var lastRunResult = RunResult.notRun

    /// A short, sanitized failure retained after Apple's NFC sheet closes.
    @Published internal private(set) var failure: String?

    /// Refreshes what is stored, without touching any secret.
    internal func refresh() {
      contents = CardCredentialStore.contents()
      allowsNearField = SupportedCardTransports.offersNearField
    }

    /// Primes the card for later system-driven logins through the selected backend.
    internal func prime(pin1: String) async {
      guard !isRunning else { return }
      if DemoMode.shared.isActive {
        await primeVirtualCard(pin1: pin1)
        return
      }
      refresh()
      guard contents.hasCardAccessNumber, allowsNearField else { return }
      // `allowsNearField` is already false below iOS 26, because the
      // system's card slot arrived there; this states the same fact in
      // the form the compiler reads.
      guard #available(iOS 26.0, *) else { return }
      isRunning = true
      lastRunResult = .notRun
      failure = nil
      let outcome = await CardPriming.prime(
        pin1: pin1,
        progress: { _ in
          // The meter on the system NFC sheet carries progress; the
          // holder is looking at the card, not at this screen.
        },
        step: { _, _ in
          // The sheet draws the steps. See `PrimingSheetReporter`.
        })
      // The sound is started and answered inside the panel's lifetime,
      // in `CardPriming`; nothing here makes a noise after it closed. A
      // hold the holder cancelled never got as far as a sound at all.
      if outcome.cancelled {
        lastRunResult = .notRun
        failure = nil
      } else if outcome.stored, outcome.registered {
        lastRunResult = .succeeded
        failure = nil
      } else {
        lastRunResult = .failed
        failure = outcome.summary
      }
      refresh()
      isRunning = false
    }

    /// Simulates only card/device effects; callers still use ``prime(pin1:)``.
    private func primeVirtualCard(pin1: String) async {
      isRunning = true
      lastRunResult = .notRun
      failure = nil
      defer { isRunning = false }
      switch await DemoMode.shared.authenticate(pin1: pin1) {
      case .success:
        lastRunResult = .succeeded
      case .invalidEntry:
        lastRunResult = .failed
        failure = String(localized: "PIN 1 does not fit its digit rules.")
      case .blocked:
        lastRunResult = .failed
        failure = String(localized: "PIN 1 is blocked.")
      case .rejected(let remaining):
        lastRunResult = .failed
        if let count = RetryCount(attemptsRemaining: remaining) {
          failure = CredentialOutcomeMessage.rejection(
            credentialName: "PIN 1",
            remaining: count)
        }
      case .refusedLowAttempts(let remaining):
        lastRunResult = .failed
        if let count = RetryCount(attemptsRemaining: remaining) {
          failure = CredentialOutcomeMessage.lowAttemptRefusal(
            credentialName: "PIN 1",
            remaining: count)
        }
      case .certificateUnavailable:
        lastRunResult = .failed
        failure = String(localized: "The card certificate could not be read.")
      case .tokenPublicationFailed:
        lastRunResult = .failed
        failure = String(localized: "Safari setup did not finish. Try again.")
      case .transportFailure:
        lastRunResult = .failed
        failure = String(localized: "The identity card could not be read. Try again.")
      }
    }
  }

#endif
