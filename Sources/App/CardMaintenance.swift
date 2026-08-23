// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Dispatch
import Foundation

/// Card activation and PIN operations over an attached reader or NFC.
///
/// A mutation, its retry-floor probe, and its resulting state read share
/// one exclusive session. An NFC action therefore presents one system
/// sheet and never opens another sheet merely to refresh counters.
internal enum CardMaintenance {
  #if REFINEID_LOCAL_CARD && os(iOS)
    /// Result of one PACE-authenticated NFC hold.
    ///
    /// A rejected CAN remains distinct because RAPP must terminate that
    /// peer session immediately; neither a missing card nor an unrelated
    /// card failure proves rejection.
    internal enum SecureNearFieldResult<Payload: Sendable>: Sendable {
      case connected(Payload)
      case failed
      case wrongCardAccessNumber
    }
  #endif

  internal enum ConnectionSnapshotResult: Sendable {
    case connected(Snapshot)
    case failed
    case wrongCardAccessNumber
  }

  private enum ConnectionFailure: Error {
    case failed
    case wrongCardAccessNumber
  }

  internal enum Outcome: Equatable, Sendable {
    case alreadyActivated
    case failed
    case floorRefused(RetryFloorVerdict)
    case invalidated
    case invalidEntry
    case noCard
    case pinBlocked
    case rejected(remaining: RetryCount)
    case success
  }

  private final class UncheckedCard: @unchecked Sendable {
    let card: TKSmartCard

    init(_ card: TKSmartCard) {
      self.card = card
    }
  }

  internal static func onCard<Answer: Sendable>(
    transport: Transport,
    cardAccessNumber: String?,
    message: String,
    _ operation: @escaping @Sendable (CardOperations) -> Answer
  ) async -> Answer? {
    switch transport {
    case .reader:
      return await onReader(
        cardAccessNumber: cardAccessNumber,
        operation
      )
    case .nearField:
      #if REFINEID_LOCAL_CARD && os(iOS)
        guard SupportedCardTransports.offersNearField else { return nil }
        // The system's card slot over the antenna arrived in iOS 26. An
        // older system has no way to hold a card, which is the same
        // answer as a device without an antenna.
        guard #available(iOS 26.0, *) else { return nil }
        let held: NearFieldCardSession
        do {
          held = try await NearFieldCardSession.open(message: message)
        } catch {
          return nil
        }
        defer { held.end() }
        return await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .userInitiated).async {
            let answer = try? held.withCardSession { channel -> Answer? in
              guard
                let operations = selectedOperations(
                  over: channel,
                  cardAccessNumber: cardAccessNumber
                )
              else {
                return nil
              }
              return operation(operations)
            }
            continuation.resume(returning: answer.flatMap(\.self))
          }
        }
      #else
        return nil
      #endif
    }
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    /// Runs one RAPP card operation in one exclusive NFC hold after PACE.
    ///
    /// The callback receives only secure-messaging `CardOperations`. It cannot
    /// retain the card, channel, or NFC slot. A caller therefore performs its
    /// fresh retry probe and the one credential-bearing command in this same
    /// callback, with no UI delay or second NFC session between them.
    internal static func onSecureNearFieldCard<Payload: Sendable>(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations) -> Payload
    ) async -> SecureNearFieldResult<Payload> {
      guard SupportedCardTransports.offersNearField else {
        #if DEBUG
          print("[near-field] refused: platform offers no antenna")
          fflush(stdout)
        #endif
        return .failed
      }
      // The system's card slot over the antenna arrived in iOS 26.
      guard #available(iOS 26.0, *) else {
        #if DEBUG
          print("[near-field] refused: system predates the card slot")
          fflush(stdout)
        #endif
        return .failed
      }
      let held: NearFieldCardSession
      do {
        held = try await NearFieldCardSession.open(message: message)
      } catch {
        #if DEBUG
          print("[near-field] open failed: \(String(describing: error))")
          fflush(stdout)
        #endif
        return .failed
      }
      defer { held.end() }
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = Self.cardSessionAnswer(held) { channel in
            do {
              let operations = try connectionOperations(
                over: channel,
                cardAccessNumber: cardAccessNumber
              )
              return SecureNearFieldResult.connected(operation(operations))
            } catch ConnectionFailure.wrongCardAccessNumber {
              return SecureNearFieldResult<Payload>.wrongCardAccessNumber
            } catch {
              #if DEBUG
                print("[near-field] connect failed: \(String(describing: error))")
                fflush(stdout)
              #endif
              return SecureNearFieldResult<Payload>.failed
            }
          }
          continuation.resume(returning: answer ?? .failed)
        }
      }
    }

    /// Runs the body on the held session, keeping what the session threw.
    ///
    /// The throwing call is the one that reports why the antenna never
    /// reached a card, and discarding it leaves every distinct refusal --
    /// no card in the field, a session the system would not grant, a card
    /// that answered nothing -- looking like the same failure.
    @available(iOS 26.0, *)
    private static func cardSessionAnswer<Payload: Sendable>(
      _ held: NearFieldCardSession,
      _ body: (SmartCardChannel) throws -> SecureNearFieldResult<Payload>
    ) -> SecureNearFieldResult<Payload>? {
      do {
        return try held.withCardSession(body)
      } catch {
        #if DEBUG
          print("[near-field] session failed: \(String(describing: error))")
          fflush(stdout)
        #endif
        return nil
      }
    }
  #endif

  /// Reader-only compatibility for signing and SCS callers.
  internal static func onCard<Answer: Sendable>(
    _ operation: @escaping @Sendable (CardOperations) -> Answer?
  ) async -> Answer? {
    let nested: Answer?? = await onCard(
      transport: .reader,
      cardAccessNumber: nil,
      message: "",
      operation
    )
    return nested.flatMap(\.self)
  }

  /// The first wireless connection, classified from the live ATR before
  /// falling back to the certificate. Unknown state is a failed connection,
  /// never evidence that the card is activated.
  #if REFINEID_LOCAL_CARD && os(iOS)
    internal static func connectionSnapshot(
      cardAccessNumber: String
    ) async -> ConnectionSnapshotResult {
      if await DemoMode.shared.isActive {
        return await DemoMode.shared.connectionSnapshot(
          cardAccessNumber: cardAccessNumber)
      }
      guard SupportedCardTransports.offersNearField else { return .failed }
      // The system's card slot over the antenna arrived in iOS 26.
      guard #available(iOS 26.0, *) else { return .failed }
      let held: NearFieldCardSession
      do {
        held = try await NearFieldCardSession.open(
          message: String(localized: "Hold the card near the top of the iPhone."))
      } catch {
        return .failed
      }
      defer { held.end() }
      let atrScheme = ActivationScheme.classify(
        answerToReset: held.answerToReset)
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = try? held.withCardSession { channel -> ConnectionSnapshotResult in
            do {
              let operations = try connectionOperations(
                over: channel,
                cardAccessNumber: cardAccessNumber)
              let certificateScheme = classifyScheme(operations)
              // The certificate issuance date is the authoritative generation
              // boundary. An NFC reset answer is only a fallback: unlike a
              // reader ATR it may describe the contactless interface rather
              // than the issued card generation.
              guard let scheme = certificateScheme ?? atrScheme else {
                return .failed
              }
              let needs = operations.activationNeeds(scheme: scheme)
              #if DEBUG
                let pin1Record = try? operations.readPinChangeRecord(role: .pin1)
                let pin2Record = try? operations.readPinChangeRecord(role: .pin2)
                let pin1Probe = try? operations.probeRetryCounter(role: .pin1)
                let pin2Probe = try? operations.probeRetryCounter(role: .pin2)
                DebugConsole.emit([
                  "connect-probe: ATR scheme \(String(describing: atrScheme))",
                  "connect-probe: certificate scheme \(String(describing: certificateScheme))",
                  "connect-probe: selected scheme \(scheme)",
                  "connect-probe: PIN1 changed \(String(describing: pin1Record))",
                  "connect-probe: PIN2 changed \(String(describing: pin2Record))",
                  "connect-probe: PIN1 retry \(String(describing: pin1Probe))",
                  "connect-probe: PIN2 retry \(String(describing: pin2Probe))",
                  "connect-probe: activation needs PIN1=\(needs.pin1) PIN2=\(needs.pin2)",
                  "connect-probe: route \(needs.any ? "activation" : "authentication")",
                ])
              #endif
              return .connected(
                Snapshot(
                  report: try? operations.probeCredentials(),
                  activationNeeds: needs,
                  activationScheme: scheme))
            } catch ConnectionFailure.wrongCardAccessNumber {
              return .wrongCardAccessNumber
            } catch {
              return .failed
            }
          }
          continuation.resume(returning: answer.flatMap(\.self) ?? .failed)
        }
      }
    }

    #if DEBUG
      /// Reads every input to activation classification from the live NFC
      /// card.
      ///
      /// This probe is deliberately observation-only: PACE plus GET
      /// DATA/VERIFY-without-data commands, never a PIN-bearing mutation.
      internal static func debugActivationSignals() async -> DebugModeReport {
        guard let cardAccessNumber = CardCredentialStore.displayedCardAccessNumber() else {
          return DebugModeReport(
            lines: ["activation-probe: no validated CAN is stored"],
            succeeded: false)
        }
        guard #available(iOS 26.0, *) else {
          return DebugModeReport(
            lines: ["activation-probe: the card slot needs iOS 26"],
            succeeded: false)
        }
        let held: NearFieldCardSession
        do {
          held = try await NearFieldCardSession.open(
            message: "Hold the factory-state card near the top of the iPhone.")
        } catch {
          return DebugModeReport(
            lines: ["activation-probe: NFC session did not open"],
            succeeded: false)
        }
        defer { held.end() }
        let atrScheme = ActivationScheme.classify(answerToReset: held.answerToReset)
        return await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .userInitiated).async {
            let report = try? held.withCardSession { channel -> DebugModeReport in
              do {
                let operations = try connectionOperations(
                  over: channel,
                  cardAccessNumber: cardAccessNumber)
                let certificateScheme = classifyScheme(operations)
                let pin1Record = try? operations.readPinChangeRecord(role: .pin1)
                let pin2Record = try? operations.readPinChangeRecord(role: .pin2)
                let pin1Probe = try? operations.probeRetryCounter(role: .pin1)
                let pin2Probe = try? operations.probeRetryCounter(role: .pin2)
                let selectedScheme = certificateScheme ?? atrScheme
                let pin1Readiness = selectedScheme.map {
                  ActivationPreflight.evaluate(
                    scheme: $0,
                    probe: pin1Probe,
                    changeRecord: pin1Record ?? .unreadable)
                }
                let pin2Readiness = selectedScheme.map {
                  ActivationPreflight.evaluate(
                    scheme: $0,
                    probe: pin2Probe,
                    changeRecord: pin2Record ?? .unreadable)
                }
                return DebugModeReport(
                  lines: [
                    "activation-probe: ATR scheme \(String(describing: atrScheme))",
                    "activation-probe: certificate scheme \(String(describing: certificateScheme))",
                    "activation-probe: PIN1 changed \(String(describing: pin1Record))",
                    "activation-probe: PIN2 changed \(String(describing: pin2Record))",
                    "activation-probe: PIN1 probe \(String(describing: pin1Probe))",
                    "activation-probe: PIN2 probe \(String(describing: pin2Probe))",
                    "activation-probe: PIN1 readiness \(String(describing: pin1Readiness))",
                    "activation-probe: PIN2 readiness \(String(describing: pin2Readiness))",
                  ],
                  succeeded: selectedScheme != nil)
              } catch {
                return DebugModeReport(
                  lines: ["activation-probe: card session failed: \(error)"],
                  succeeded: false)
              }
            }
            continuation.resume(
              returning: report.flatMap(\.self)
                ?? DebugModeReport(
                  lines: ["activation-probe: card session unavailable"],
                  succeeded: false))
          }
        }
      }
    #endif
  #else
    // The first wireless connection is an iOS-only operation.
    //
    // Keeping the unavailable implementation explicit lets shared UI
    // models compile for macOS without pretending that a reader session
    // is an NFC setup flow. The signature stays async so shared callers
    // await one shape on both platforms.
    // swiftlint:disable async_without_await
    internal static func connectionSnapshot(
      cardAccessNumber _: String
    ) async -> ConnectionSnapshotResult {
      .failed
    }
  // swiftlint:enable async_without_await
  #endif

  /// Establishes the first PACE channel while preserving a rejected CAN
  /// as a distinct, recoverable result.
  private static func connectionOperations(
    over channel: SmartCardChannel,
    cardAccessNumber: String
  ) throws -> CardOperations {
    let operations = CardOperations(channel: channel)
    do {
      try operations.selectFineidApplication()
      return operations
    } catch CardOperationError.selectRejected(.securityNotSatisfied) {
      guard let offered = CardAccessNumber(digits: cardAccessNumber) else {
        throw ConnectionFailure.failed
      }
      try? operations.selectMasterFile()
      let keys: PaceSessionKeys
      do {
        keys = try PaceEstablishment(channel: channel).establish(with: offered)
      } catch PaceEstablishment.Failure.authenticationTokenMismatch {
        throw ConnectionFailure.wrongCardAccessNumber
      } catch PaceEstablishment.Failure.cardRejected(.authenticationFailed) {
        // A FINEID card may reject the terminal's final PACE token with
        // 6300 instead of returning its own token for local comparison.
        // Both outcomes mean the CAN-derived session keys did not match.
        throw ConnectionFailure.wrongCardAccessNumber
      } catch {
        throw ConnectionFailure.failed
      }
      let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
      let secureOperations = CardOperations(channel: secure)
      guard (try? secureOperations.selectFineidApplication()) != nil else {
        throw ConnectionFailure.failed
      }
      return secureOperations
    } catch {
      throw ConnectionFailure.failed
    }
  }

  private static func onReader<Answer: Sendable>(
    cardAccessNumber: String?,
    _ operation: @escaping @Sendable (CardOperations) -> Answer
  ) async -> Answer? {
    guard let manager = TKSmartCardSlotManager.default else { return nil }
    let occupied = await CardSlotSearch.allOccupied(in: manager).filter { occupiedSlot in
      CardTransport.transport(forSlotNamed: occupiedSlot.name) == .reader
    }
    let cards = occupied.compactMap { occupiedSlot in
      occupiedSlot.slot.makeSmartCard().map(UncheckedCard.init)
    }
    guard !cards.isEmpty else { return nil }
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        for candidate in cards {
          let answer = try? SmartCardChannel(candidate.card).withSession {
            channel -> Answer? in
            guard
              let operations = selectedOperations(
                over: channel,
                cardAccessNumber: cardAccessNumber
              )
            else {
              return nil
            }
            return operation(operations)
          }
          if let value = answer.flatMap(\.self) {
            continuation.resume(returning: value)
            return
          }
        }
        continuation.resume(returning: nil)
      }
    }
  }

  private static func selectedOperations(
    over channel: SmartCardChannel,
    cardAccessNumber: String?
  ) -> CardOperations? {
    let operations = CardOperations(channel: channel)
    do {
      try operations.selectFineidApplication()
      return operations
    } catch CardOperationError.selectRejected(.securityNotSatisfied) {
      let offered =
        cardAccessNumber.flatMap(CardAccessNumber.init(digits:))
        ?? CardCredentialStore.cardAccessNumber()
      guard let offered else { return nil }
      try? operations.selectMasterFile()
      let keys: PaceSessionKeys
      do {
        keys = try PaceEstablishment(channel: channel).establish(with: offered)
      } catch PaceEstablishment.Failure.authenticationTokenMismatch {
        CardCredentialStore.forgetCardAccessNumber()
        return nil
      } catch PaceEstablishment.Failure.cardRejected(.authenticationFailed) {
        CardCredentialStore.forgetCardAccessNumber()
        return nil
      } catch {
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
