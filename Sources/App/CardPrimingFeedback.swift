#if canImport(CoreNFC) && os(iOS)

  import AudioToolbox
  import UIKit

  /// Says out loud how a card hold ended.
  ///
  /// The system NFC sheet cannot: `TKSmartCardSlotNFCSession` carries a
  /// message and `endSession` and nothing else, so it dismisses with the
  /// same checkmark whether the hold registered an identity or died at
  /// PACE. A holder who was watching the card rather than the screen has
  /// otherwise been told nothing, and a badly held card looks exactly
  /// like a good one.
  ///
  /// Both channels are the system's own. The haptic is
  /// `UINotificationFeedbackGenerator`, which is what every other iOS
  /// success and failure feels like, and the sound is a system sound the
  /// holder already knows -- neither is a recording this app ships. Both
  /// respect the phone's own switches: a silenced phone plays nothing,
  /// and a phone with haptics off feels nothing.
  @MainActor
  internal enum CardPrimingFeedback {
    /// The system sound played when a hold ends without an identity.
    ///
    /// `SystemSoundID` 1073 is the standard alert tone; it is deliberately
    /// the one the holder already associates with a refused action rather
    /// than something this app invents.
    private static let failureSoundID: SystemSoundID = 1_073

    /// The system sound played when a hold ends with an identity.
    ///
    /// 1057 is the standard completion tone.
    private static let successSoundID: SystemSoundID = 1_057

    /// Reports the outcome by haptic and sound together.
    ///
    /// Both, because either alone is missable: a phone in a pocket is
    /// felt and not heard, a phone on a desk is heard and not felt.
    internal static func report(succeeded: Bool) {
      let generator = UINotificationFeedbackGenerator()
      generator.notificationOccurred(succeeded ? .success : .error)
      AudioServicesPlaySystemSound(succeeded ? Self.successSoundID : Self.failureSoundID)
    }
  }

#endif
