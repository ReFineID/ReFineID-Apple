#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Dispatch

  /// Reads the serial of a present card.
  ///
  /// A contact insertion answers freely -- physical possession is the
  /// access control there. A card on an antenna is sealed until PACE
  /// and offers nothing card-unique before it, by design; when a card
  /// access number is stored, the probe unseals the way the driver
  /// does and reads the serial through the secure channel. A wrong
  /// number costs one refused handshake and answers nil.
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

    /// One exclusive session: SELECT, and the serial when it answers,
    /// unsealing first when the card asks to be.
    private static func readBlocking(_ smartCard: TKSmartCard) -> TokenSerial? {
      let serial = try? SmartCardChannel(smartCard).withSession { channel -> TokenSerial? in
        let operations = CardOperations(channel: channel)
        do {
          try operations.selectFineidApplication()
        } catch CardOperationError.selectRejected(.securityNotSatisfied) {
          return Self.unsealedSerial(over: channel)
        }
        return try operations.readTokenSerial()
      }
      return serial.flatMap(\.self)
    }

    /// PACE with the stored number, then the serial through the secure
    /// channel; nil when no number is stored or the card refuses it.
    private static func unsealedSerial(over channel: SmartCardChannel) -> TokenSerial? {
      guard let number = CardCredentialStore.cardAccessNumber() else { return nil }
      try? CardOperations(channel: channel).selectMasterFile()
      guard let keys = try? PaceEstablishment(channel: channel).establish(with: number) else {
        return nil
      }
      let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
      let operations = CardOperations(channel: secure)
      guard (try? operations.selectFineidApplication()) != nil else { return nil }
      return try? operations.readTokenSerial()
    }
  }

#endif
