#if os(macOS)

  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Dispatch
  import Security

  /// One credential operation against the present card, in one
  /// exclusive session: the retry-floor probe first, then the
  /// operation, and never a credential spent below the floor.
  ///
  /// The same session rules as `CardSerialProbe`: a contact insertion
  /// answers freely, a card on the antenna is unsealed with the stored
  /// card access number, and the blocking card I/O stays off the
  /// cooperative pool. Entries cross into the blocking closure as
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

    /// What one qualified signing session produced.
    internal struct QualifiedProduct {
      /// The card's raw signature.
      internal let signature: Data

      /// The exact attribute bytes it covers.
      internal let attributes: Data

      /// The certificate that will verify it.
      internal let certificate: Data
    }

    /// The result of one qualified signing session.
    internal enum QualifiedAnswer {
      /// The card refused, at the floor or at the credential.
      case refused(Outcome)

      /// The card signed.
      case signed(QualifiedProduct)
    }

    /// Reads the qualified certificate, verifies PIN2 and signs the
    /// attributes the caller builds from it - one session, one PIN2,
    /// one signature.
    ///
    /// The attributes cannot be built before the session because they
    /// hash the certificate, and the certificate is on the card.
    internal static func qualifiedSignature(
      pin2: String,
      digestBuilder: @escaping @Sendable (Data) -> Data
    ) async -> QualifiedAnswer {
      let result = await onCard { operations in
        Self.qualifiedInSession(operations, pin2: pin2, builder: digestBuilder)
      }
      return result ?? .refused(.noCard)
    }

    /// The qualified signature, inside an open session: floor, the
    /// certificate, PIN2, then the one signature it authorises.
    private static func qualifiedInSession(
      _ operations: CardOperations,
      pin2: String,
      builder: (Data) -> Data
    ) -> QualifiedAnswer {
      guard let probe = try? operations.probeRetryCounter(role: .pin2) else {
        return .refused(.floorRefused(.refuseUnreadable))
      }
      let verdict = RetryFloor.evaluate(probeOutcome: probe)
      guard verdict == .proceed else {
        return .refused(.floorRefused(verdict))
      }
      guard
        let certificate = try? operations.readCertificate(.qualifiedSignature)
      else {
        return .refused(.failed)
      }
      guard let credential = Pin2(digits: pin2) else {
        return .refused(.invalidEntry)
      }
      do {
        try operations.verifyPin2(credential.consumeForSingleTransmission())
      } catch {
        return .refused(outcome(of: error))
      }
      let attributes = builder(certificate)
      let digest = Data(SHA384.hash(data: attributes))
      guard
        let length = ExpectedResponseLength(
          count: FineidSignatureLengths.ecdsaP384
        ),
        let signature = try? operations.computeQualifiedSignature(
          overDigest: digest,
          algorithm: SigningAlgorithm(hash: .sha384, scheme: .ecdsa),
          expectedSignatureLength: length
        )
      else {
        return .refused(.failed)
      }
      return .signed(
        QualifiedProduct(
          signature: signature,
          attributes: attributes,
          certificate: certificate
        )
      )
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
    internal static func onCard<Answer: Sendable>(
      _ work: @escaping @Sendable (CardOperations) -> Answer?
    ) async -> Answer? {
      guard let manager = TKSmartCardSlotManager.default,
        let found = await CardSlotSearch.occupied(in: manager),
        let smartCard = found.slot.makeSmartCard()
      else {
        return nil
      }
      let carried = UncheckedCard(smartCard)
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = try? SmartCardChannel(carried.card).withSession {
            channel -> Answer? in
            guard let operations = Self.selectedOperations(over: channel) else {
              return nil
            }
            return work(operations)
          }
          continuation.resume(returning: answer.flatMap(\.self))
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
