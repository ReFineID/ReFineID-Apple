#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Dispatch
  import Foundation

  /// One credential operation against the present card, in one
  /// exclusive session: the retry-floor probe first, then the
  /// operation, and never a credential spent below the floor.
  ///
  /// Session rules: a contact insertion answers freely, a card on the
  /// antenna is unsealed with the access number the holder entered for
  /// it, and the blocking card I/O stays off the cooperative pool. Entries cross into the blocking closure as
  /// strings and become their typed, consume-once forms there - a
  /// noncopyable value cannot be captured by the escaping hop.
  internal enum CardMaintenance {
    /// What one management operation answered.
    internal enum Outcome: Equatable, Sendable {
      /// The card shows evidence of prior activation and the flow was
      /// not told to override.
      case alreadyActivated

      /// The card refused in a way nothing here models.
      case failed

      /// The retry floor refused before any credential was sent.
      case floorRefused(RetryFloorVerdict)

      /// The credential slot is invalidated; issuer recovery only.
      case invalidated

      /// Local validation refused an entry; the card was not touched.
      case invalidEntry

      /// No readable card: absent, sealed without a stored number, or
      /// no session.
      case noCard

      /// The presented credential is blocked.
      case pinBlocked

      /// The card rejected the presented credential.
      case rejected(remaining: RetryCount)

      /// The operation completed.
      case success
    }

    /// The two activation steps' outcomes; PIN2 nil when not attempted.
    internal struct ActivationReport: Equatable, Sendable {
      /// How this card activates, classified from its certificate.
      internal let scheme: ActivationScheme

      /// The PIN1 step's outcome.
      internal let pin1: Outcome

      /// The PIN2 step's outcome; nil when PIN1 did not succeed.
      internal let pin2: Outcome?
    }

    /// Carries the non-Sendable card onto the background queue; touched
    /// only there.
    private final class UncheckedCard: @unchecked Sendable {
      let card: TKSmartCard

      init(_ card: TKSmartCard) {
        self.card = card
      }
    }

    /// One counter-safe reading of all three credentials.
    internal static func probeCredentials() async -> CredentialProbeReport? {
      await onCard { operations in
        try? operations.probeCredentials()
      }
    }

    /// Changes PIN1 behind the PIN1 retry floor.
    internal static func changePin1(current: String, new: String) async -> Outcome {
      await withFloor(.pin1) { operations in
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

    /// Changes PIN2 behind the PIN2 retry floor.
    internal static func changePin2(current: String, new: String) async -> Outcome {
      await withFloor(.pin2) { operations in
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

    /// Unblocks PIN1 with the PUK, behind the PUK's retry floor - a
    /// wrong PUK spends the PUK, and exhausting it is terminal.
    internal static func unblockPin1(puk: String, new: String) async -> Outcome {
      await withFloor(.puk) { operations in
        guard
          let unblockKey = Puk(digits: puk),
          let newPin = Pin1(digits: new)
        else {
          return .invalidEntry
        }
        do {
          try operations.unblockPin1(
            puk: unblockKey.consumeForSingleTransmission(),
            new: newPin.consumeForSingleTransmission()
          )
          return .success
        } catch {
          return outcome(of: error)
        }
      }
    }

    /// Unblocks PIN2 with the PUK, behind the PUK's retry floor.
    internal static func unblockPin2(puk: String, new: String) async -> Outcome {
      await withFloor(.puk) { operations in
        guard
          let unblockKey = Puk(digits: puk),
          let newPin = Pin2(digits: new)
        else {
          return .invalidEntry
        }
        do {
          try operations.unblockPin2(
            puk: unblockKey.consumeForSingleTransmission(),
            new: newPin.consumeForSingleTransmission()
          )
          return .success
        } catch {
          return outcome(of: error)
        }
      }
    }

    /// Opens the session, probes the floor for the credential the
    /// operation will present, and runs it only on a clean verdict.
    private static func withFloor(
      _ role: CredentialRole,
      _ operation: @escaping @Sendable (CardOperations) -> Outcome
    ) async -> Outcome {
      let result = await onCard { operations -> Outcome in
        guard let probe = try? operations.probeRetryCounter(role: role) else {
          return .floorRefused(.refuseUnreadable)
        }
        let verdict = RetryFloor.evaluate(probeOutcome: probe)
        guard verdict == .proceed else {
          return .floorRefused(verdict)
        }
        return operation(operations)
      }
      return result ?? .noCard
    }

    /// Finds the present card, opens one exclusive session, selects the
    /// eID application (unsealing with the stored number when the card
    /// asks), and hands typed operations to `work` on the background
    /// queue.
    ///
    /// Every occupied slot is tried until one yields a selected
    /// application: a dual-interface reader can present the same card
    /// on its contact and contactless slots at once, and only the
    /// contact one is usable without PACE - stopping at whichever
    /// slot enumerates first made the card unreachable whenever the
    /// antenna's slot came up before the contact one.
    internal static func onCard<Answer: Sendable>(
      _ work: @escaping @Sendable (CardOperations) -> Answer?
    ) async -> Answer? {
      guard let manager = TKSmartCardSlotManager.default else { return nil }
      let occupied = await CardSlotSearch.allOccupied(in: manager)
      let carried = occupied.compactMap { candidate in
        candidate.slot.makeSmartCard().map(UncheckedCard.init)
      }
      guard !carried.isEmpty else { return nil }
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          for candidate in carried {
            let answer = try? SmartCardChannel(candidate.card).withSession {
              channel -> Answer? in
              guard let operations = Self.selectedOperations(over: channel) else {
                return nil
              }
              return work(operations)
            }
            if let unwrapped = answer.flatMap(\.self) {
              continuation.resume(returning: unwrapped)
              return
            }
          }
          continuation.resume(returning: nil)
        }
      }
    }

    /// Selects the eID application, running PACE with the stored card
    /// access number when the contactless interface asks for it.
    private static func selectedOperations(
      over channel: SmartCardChannel
    ) -> CardOperations? {
      let operations = CardOperations(channel: channel)
      do {
        try operations.selectFineidApplication()
        return operations
      } catch CardOperationError.selectRejected(.securityNotSatisfied) {
        guard let number = CardCredentialStore.cardAccessNumber() else {
          return nil
        }
        try? operations.selectMasterFile()
        guard
          let keys = try? PaceEstablishment(channel: channel).establish(
            with: number
          )
        else {
          return nil
        }
        let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
        let secureOperations = CardOperations(channel: secure)
        guard (try? secureOperations.selectFineidApplication()) != nil else {
          return nil
        }
        return secureOperations
      } catch {
        return nil
      }
    }

    /// Names what the card's refusal was.
    internal static func outcome(of error: Error) -> Outcome {
      switch error {
      case CardOperationError.pinRejected(let remaining):
        .rejected(remaining: remaining)
      case CardOperationError.pinBlocked:
        .pinBlocked
      case CardOperationError.credentialInvalidated:
        .invalidated
      default:
        .failed
      }
    }
  }

#endif
