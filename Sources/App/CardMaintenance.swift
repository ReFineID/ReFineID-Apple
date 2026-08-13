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
      #if canImport(CoreNFC) && os(iOS)
        guard SupportedCardTransports.offersNearField else { return nil }
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
      guard
        let keys = try? PaceEstablishment(channel: channel).establish(with: offered)
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
