// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// The scan sheet a demonstration opens, with no card under it.
  ///
  /// The phone's own panel, opened the way a card read opens it and
  /// carrying the same line of text, under the same provisioning tone.
  /// Nothing is transmitted: no session is begun, no byte is sent, and
  /// the panel closes on a timer rather than on an answer.
  ///
  /// A device with no antenna waits the same time without a panel. Every
  /// iPad is such a device, and a demonstration that cannot run on the
  /// reviewer's device demonstrates nothing.
  @available(iOS 26.0, *)
  @MainActor
  internal enum DemoCardHold {
    /// How long the panel stays up, in seconds.
    ///
    /// One phrase of the provisioning tone, which is about what a hold
    /// costs when the card was already stored on this iPhone.
    private static let holdSeconds: Int = 3

    /// The same, as the sleep wants it.
    private static let holdDuration: Duration = .seconds(Self.holdSeconds)

    /// Opens the panel, waits, and closes it.
    internal static func run() async {
      CardPrimingFeedback.startWorking()
      let panel = await Self.openPanel()
      try? await Task.sleep(for: Self.holdDuration)
      panel?.end()
      CardPrimingFeedback.report(succeeded: true)
    }

    /// The system panel, or nil when this device has no antenna.
    private static func openPanel() async -> TKSmartCardSlotNFCSession? {
      guard SupportedCardTransports.offersNearField,
        let manager = TKSmartCardSlotManager.default
      else {
        return nil
      }
      return await withCheckedContinuation { continuation in
        manager.createNFCSlot(message: CardPriming.holdMessage) { opened, _ in
          continuation.resume(returning: opened)
        }
      }
    }
  }

#endif
