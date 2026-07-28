#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Dispatch

  /// Asks the present card who it is: serial, model key, model name.
  ///
  /// A contact insertion answers freely -- physical possession is the
  /// access control there. A card on an antenna is sealed until PACE
  /// and offers nothing card-unique before it, by design; given digits
  /// (or a stored single number) the probe unseals the way the driver
  /// does and reads the serial through the secure channel. A wrong
  /// number costs one refused handshake and answers nil.
  internal enum CardSerialProbe {
    /// What one look at the present card answered.
    internal struct Reading {
      /// The card's token serial, unique to the card.
      internal let serial: TokenSerial

      /// Hex of the ATR historical bytes: the model, never the card.
      internal let modelKey: String

      /// What to call the card on screen.
      internal let model: String
    }

    /// Carries the non-Sendable card onto the background queue; touched
    /// only there.
    private final class UncheckedCard: @unchecked Sendable {
      let card: TKSmartCard

      init(_ card: TKSmartCard) {
        self.card = card
      }
    }

    /// Reads the present card's identity, or nil when nothing answers.
    ///
    /// `digits` unseals a sealed card; absent, the stored single number
    /// stands in.
    internal static func read(unsealingWith digits: String?) async -> Reading? {
      guard let manager = TKSmartCardSlotManager.default,
        let found = await CardSlotSearch.occupied(in: manager),
        let smartCard = found.slot.makeSmartCard()
      else {
        return nil
      }
      let answerToReset = found.slot.atr?.bytes
      guard let modelKey = answerToReset.flatMap({ AnswerToReset(bytes: $0)?.modelKey }) else {
        return nil
      }
      let model =
        answerToReset.flatMap { CardTypeIdentification.identify(answerToReset: $0)?.name }
        ?? String(localized: "Identity card")
      let carried = UncheckedCard(smartCard)
      // The card I/O is synchronous and blocking; keep it off the
      // cooperative pool, same as the status snapshot does.
      let serial = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: Self.readBlocking(carried.card, unsealingWith: digits))
        }
      }
      guard let serial else { return nil }
      return Reading(serial: serial, modelKey: modelKey, model: model)
    }

    /// One exclusive session: SELECT, and the serial when it answers,
    /// unsealing first when the card asks to be.
    private static func readBlocking(
      _ smartCard: TKSmartCard,
      unsealingWith digits: String?
    ) -> TokenSerial? {
      let serial = try? SmartCardChannel(smartCard).withSession { channel -> TokenSerial? in
        let operations = CardOperations(channel: channel)
        do {
          try operations.selectFineidApplication()
        } catch CardOperationError.selectRejected(.securityNotSatisfied) {
          return Self.unsealedSerial(over: channel, unsealingWith: digits)
        }
        return try operations.readTokenSerial()
      }
      return serial.flatMap(\.self)
    }

    /// PACE, then the serial through the secure channel; nil when there
    /// is no number to try or the card refuses it.
    private static func unsealedSerial(
      over channel: SmartCardChannel,
      unsealingWith digits: String?
    ) -> TokenSerial? {
      let typed = digits.flatMap(CardAccessNumber.init(digits:))
      guard let number = typed ?? CardCredentialStore.cardAccessNumber() else { return nil }
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
