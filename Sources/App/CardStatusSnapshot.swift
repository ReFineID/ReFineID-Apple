import CardCore
import CryptoTokenKit
import Foundation

/// One captured reading of reader, card, and credential state.
///
/// Captured on demand (manual or on-appear refresh; never polling, per
/// the release plan) inside one exclusive card session that is ended
/// before the snapshot returns.
internal struct CardStatusSnapshot: Equatable, Sendable {
  /// Why a capture could not produce card state.
  internal enum CaptureFailure: Equatable, Sendable {
    /// The card answered, but not readably.
    case cardUnreadable

    /// TKSmartCardSlotManager is unavailable on this device.
    case serviceUnavailable

    /// The exclusive session could not begin (contention or teardown).
    case sessionUnavailable
  }

  /// What the card slot held at capture time.
  internal enum CardState: Equatable, Sendable {
    /// Something failed; the typed reason is displayable.
    case failed(CaptureFailure)

    /// No card is present in the reader.
    case noCard

    /// A supported card and its counter-safe probe report.
    case supported(CredentialProbeReport)

    /// A card without the FINEID application.
    case unsupported
  }

  /// Carries the non-Sendable card into the background queue closure; the
  /// card is only touched on that one queue, serially.
  private final class UncheckedCard: @unchecked Sendable {
    let card: TKSmartCard

    init(_ card: TKSmartCard) {
      self.card = card
    }
  }

  /// Token identifiers published by this driver carry this prefix
  /// (both the historical and current class identifiers).
  private static let tokenPrefix = "fi.refineid."

  /// The reader's name, or nil when no reader is attached.
  internal let readerName: String?

  /// The card state behind that reader.
  internal let card: CardState

  /// True when a ReFineID token is currently published to the system -
  /// the public-API answer to "can Safari use the card right now?"
  /// (TKTokenWatcher; release plan section 5 forbids claiming more).
  internal let safariIdentityPresent: Bool

  /// Captures a fresh snapshot: discovers the first slot, then runs one
  /// exclusive card session on a background queue (the card I/O is
  /// synchronous and blocking, so it must not stall Swift concurrency).
  internal static func capture() async -> Self {
    let tokenPresent = TKTokenWatcher().tokenIDs.contains { tokenID in
      tokenID.hasPrefix(Self.tokenPrefix)
    }
    guard let manager = TKSmartCardSlotManager.default else {
      return Self(
        readerName: nil,
        card: .failed(.serviceUnavailable),
        safariIdentityPresent: tokenPresent
      )
    }
    guard let slotName = manager.slotNames.first else {
      return Self(readerName: nil, card: .noCard, safariIdentityPresent: tokenPresent)
    }
    guard
      let slot = await manager.getSlot(withName: slotName),
      let smartCard = slot.makeSmartCard()
    else {
      return Self(
        readerName: slotName,
        card: .noCard,
        safariIdentityPresent: tokenPresent
      )
    }
    let cardState = await readCardOffMainThread(smartCard)
    return Self(
      readerName: slotName,
      card: cardState,
      safariIdentityPresent: tokenPresent
    )
  }

  /// Runs the synchronous, blocking card session on a background GCD
  /// queue and bridges the result back - never on the cooperative pool.
  private static func readCardOffMainThread(_ smartCard: TKSmartCard) async -> CardState {
    let boxed = UncheckedCard(smartCard)
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: readCard(boxed.card))
      }
    }
  }

  /// Opens one exclusive session against the card and classifies it.
  private static func readCard(_ smartCard: TKSmartCard) -> CardState {
    do {
      return try SmartCardChannel(smartCard).withSession { channel in
        let operations = CardOperations(channel: channel)
        do {
          try operations.selectFineidApplication()
        } catch CardOperationError.selectRejected {
          return .unsupported
        }
        return .supported(try operations.probeCredentials())
      }
    } catch CardOperationError.sessionUnavailable {
      return .failed(.sessionUnavailable)
    } catch {
      return .failed(.cardUnreadable)
    }
  }
}
