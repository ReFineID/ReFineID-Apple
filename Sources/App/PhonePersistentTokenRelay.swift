// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && canImport(CoreNFC)
  import CardCore
  import Foundation

  /// Keeps the phone visible on the encrypted relay and performs only the card
  /// operation requested by the Mac. CAN and PIN 1 remain in this process.
  @MainActor
  internal final class PhonePersistentTokenRelay {
    internal static let shared = PhonePersistentTokenRelay()

    private var relay: PersistentRelaySession?
    private var isBusy = false

    private init() {}

    internal func start() {
      guard relay == nil else { return }
      let relay = PersistentRelaySession(
        role: .cardHolder,
        displayName: "ReFineID iPhone"
      ) { [weak self] event in
        Task { @MainActor in
          self?.receive(event)
        }
      }
      self.relay = relay
      relay.start()
    }

    private func receive(_ event: PersistentRelayEvent) {
      switch event {
      case .connected:
        break
      case .message(let message):
        serve(message)
      case .closed:
        relay = nil
        isBusy = false
        Task { @MainActor in
          await Task.yield()
          self.start()
        }
      }
    }

    private func serve(_ message: PersistentRelayMessage) {
      let id = message.requestID
      guard !isBusy else {
        try? relay?.send(.failure(id: id, reason: .busy))
        return
      }
      let respondingRelay = relay
      switch message {
      case .identityRequest:
        isBusy = true
        Task { @MainActor in
          let response: PersistentRelayMessage = switch await PhoneRelayCard.identity() {
          case .success(let certificate):
            .identityResponse(id: id, certificateDER: certificate)
          case .failure(let reason):
            .failure(id: id, reason: reason)
          }
          try? respondingRelay?.send(response)
          self.isBusy = false
        }
      case .signatureRequest(_, let profile, let algorithm, let digest):
        isBusy = true
        Task { @MainActor in
          let response: PersistentRelayMessage = switch await PhoneRelayCard.sign(
            profile: profile,
            algorithm: algorithm,
            digest: digest
          ) {
          case .success(let signature):
            .signatureResponse(id: id, signature: signature)
          case .failure(let reason):
            .failure(id: id, reason: reason)
          }
          try? respondingRelay?.send(response)
          self.isBusy = false
        }
      case .identityResponse, .signatureResponse, .failure:
        break
      }
    }
  }

  /// One fresh NFC field per identity read or signature request.
  private enum PhoneRelayCard {
  typealias Answer<Value: Sendable> = Result<Value, PersistentRelayFailure>

    static func identity() async -> Answer<Data> {
      await withSelectedCard(
        message: String(localized: "Hold the identity card near the top of the iPhone.")
      ) { operations in
        do {
          return .success(try operations.readCertificate(.authentication))
        } catch {
          return .failure(.invalidCard)
        }
      }
    }

    static func sign(
      profile: PersistentRelayCardProfile,
      algorithm: PersistentRelaySigningAlgorithm,
      digest: Data
    ) async -> Answer<Data> {
      await withSelectedCard(
        message: String(localized: "Hold the identity card still while Safari signs in.")
      ) { operations in
        guard
          let request = SignRequest.resolve(
            profile: profile.cardKeyProfile,
            algorithm: algorithm.signingAlgorithm,
            digest: digest
          )
        else {
          return .failure(.unsupportedAlgorithm)
        }
        guard let pin1 = CardCredentialStore.pin1() else {
          return .failure(.missingPIN1)
        }
        do {
          let probe = try operations.probeRetryCounter(role: .pin1)
          guard RetryFloor.evaluate(probeOutcome: probe) == .proceed else {
            return .failure(.pin1RetryFloor)
          }
          try operations.verifyPin1(pin1.consumeForSingleTransmission())
          let raw = try operations.computeAuthenticationSignature(
            overDigest: request.digest,
            algorithm: request.algorithm,
            expectedSignatureLength: request.expectedSignatureLength
          )
          guard let signature = request.wireSignature(from: raw) else {
            return .failure(.communication)
          }
          return .success(signature)
        } catch CardOperationError.pinRejected(let remaining) {
          CardCredentialStore.forgetPin1()
          return .failure(.pin1Rejected(remaining: Int(remaining.attemptsRemaining)))
        } catch CardOperationError.pinBlocked {
          CardCredentialStore.forgetPin1()
          return .failure(.pin1Blocked)
        } catch CardOperationError.credentialInvalidated {
          CardCredentialStore.forgetPin1()
          return .failure(.pin1Blocked)
        } catch {
          return .failure(.communication)
        }
      }
    }

    private static func withSelectedCard<Value: Sendable>(
      message: String,
      _ operation: @escaping @Sendable (CardOperations) -> Answer<Value>
    ) async -> Answer<Value> {
      guard let accessNumber = CardCredentialStore.cardAccessNumber() else {
        return .failure(.missingCardAccessNumber)
      }
      let session: NearFieldCardSession
      do {
        session = try await NearFieldCardSession.open(message: message)
      } catch {
        return .failure(.cardUnavailable)
      }
      defer { session.end() }
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer: Answer<Value>
          do {
            answer = try session.withCardSession { channel in
              let plain = CardOperations(channel: channel)
              try? plain.selectMasterFile()
              let keys: PaceSessionKeys
              do {
                keys = try PaceEstablishment(channel: channel).establish(
                  with: accessNumber
                )
              } catch PaceEstablishment.Failure.authenticationTokenMismatch {
                // This is an explicit CAN rejection, not a radio or reader
                // failure. It invalidates both the visible and persistent CAN.
                CardCredentialStore.forgetCardAccessNumber()
                return .failure(.wrongCardAccessNumber)
              }
              let operations = CardOperations(
                channel: SecureMessagingChannel(
                  wrapping: channel,
                  sessionKeys: keys
                )
              )
              do {
                try operations.selectFineidApplication()
              } catch {
                return .failure(.invalidCard)
              }
              return operation(operations)
            }
          } catch {
            answer = .failure(.communication)
          }
          continuation.resume(returning: answer)
        }
      }
    }
  }
#endif
