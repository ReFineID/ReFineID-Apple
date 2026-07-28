#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Dispatch

  /// Reads the serial of a present card when the card answers it
  /// without a card access number.
  ///
  /// A contact insertion answers freely -- physical possession is the
  /// access control there. A card on an antenna is sealed until PACE
  /// and offers nothing card-unique before it, by design, so this probe
  /// answers nil for it after one SELECT.
  internal enum CardSerialProbe {
    /// Carries the non-Sendable card onto the background queue; touched
    /// only there.
    private final class UncheckedCard: @unchecked Sendable {
      let card: TKSmartCard

      init(_ card: TKSmartCard) {
        self.card = card
      }
    }

    /// The present card's serial, or nil when no card answers one.
    internal static func read() async -> TokenSerial? {
      guard let manager = TKSmartCardSlotManager.default,
        let found = await CardSlotSearch.occupied(in: manager),
        let smartCard = found.slot.makeSmartCard()
      else {
        return nil
      }
      let carried = UncheckedCard(smartCard)
      // The card I/O is synchronous and blocking; keep it off the
      // cooperative pool, same as the status snapshot does.
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: Self.readBlocking(carried.card))
        }
      }
    }

    /// One exclusive session: SELECT, and the serial when it answers.
    private static func readBlocking(_ smartCard: TKSmartCard) -> TokenSerial? {
      let serial = try? SmartCardChannel(smartCard).withSession { channel -> TokenSerial? in
        let operations = CardOperations(channel: channel)
        do {
          try operations.selectFineidApplication()
        } catch CardOperationError.selectRejected(.securityNotSatisfied) {
          return nil
        }
        return try operations.readTokenSerial()
      }
      return serial.flatMap(\.self)
    }
  }

#endif
