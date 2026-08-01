#if canImport(CoreNFC) && os(iOS)

  import AudioToolbox
  import UIKit

  /// Says out loud that a hold is running, and how it ended.
  ///
  /// The system NFC sheet cannot: `TKSmartCardSlotNFCSession` carries a
  /// message and `endSession` and nothing else, so it dismisses with the
  /// same checkmark whether the hold registered an identity or died at
  /// PACE. A holder is also looking at the card rather than the screen
  /// for the several seconds a hold takes, which is exactly when they
  /// most need to know it is still working.
  ///
  /// So there are three sounds and they mean three different things: a
  /// quiet tick that repeats for as long as the card is being read, one
  /// bright tone when an identity is registered, and one blunt tone when
  /// it is not. The tick is what makes the two outcomes legible -- it
  /// stops, and what replaces it is the answer.
  ///
  /// Every sound is a system tone and every haptic is
  /// `UINotificationFeedbackGenerator`, so both are what the rest of iOS
  /// already sounds and feels like, and both obey the phone's own
  /// switches: a silenced phone plays nothing, a phone with haptics off
  /// feels nothing.
  @MainActor
  internal enum CardPrimingFeedback {
    /// The repeating tick, running while the hold is.
    private static var ticking: Task<Void, Never>?

    /// `SystemSoundID` 1104, the keyboard tock: quiet enough to repeat
    /// for several seconds without becoming an alarm.
    private static let workingSoundID: SystemSoundID = 1_104

    /// `SystemSoundID` 1057, the bright completion tink.
    private static let successSoundID: SystemSoundID = 1_057

    /// `SystemSoundID` 1073, the blunt alert tone.
    ///
    /// Deliberately not a quieter or prettier one: this is the sound
    /// that has to reach a holder who has already looked away and
    /// believes it worked.
    private static let failureSoundID: SystemSoundID = 1_073

    /// How long between two ticks, in milliseconds.
    private static let tickMilliseconds: Int = 700

    /// The tick period as the sleep takes it.
    private static let tickInterval: Duration = .milliseconds(Self.tickMilliseconds)

    /// Starts the tick that says the hold is still running.
    ///
    /// Safe to call twice: a second start replaces the first rather than
    /// layering a second tick over it.
    internal static func startWorking() {
      Self.stopWorking()
      Self.ticking = Task { @MainActor in
        while !Task.isCancelled {
          AudioServicesPlaySystemSound(Self.workingSoundID)
          try? await Task.sleep(for: Self.tickInterval)
        }
      }
    }

    /// Stops the tick and reports the outcome, by sound and by haptic.
    ///
    /// Both channels, because either alone is missable: a phone in a
    /// pocket is felt and not heard, one on a desk is heard and not
    /// felt.
    internal static func report(succeeded: Bool) {
      Self.stopWorking()
      let generator = UINotificationFeedbackGenerator()
      generator.notificationOccurred(succeeded ? .success : .error)
      AudioServicesPlaySystemSound(succeeded ? Self.successSoundID : Self.failureSoundID)
    }

    /// Ends the tick without saying anything about the outcome.
    internal static func stopWorking() {
      Self.ticking?.cancel()
      Self.ticking = nil
    }
  }

#endif
