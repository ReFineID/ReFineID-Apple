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
  /// quiet tick that repeats for as long as the card is being read, the
  /// system's own card-read pling when an identity is registered, and
  /// its own card-read failure tone when one is not. The tick is what
  /// makes the two outcomes legible -- it stops, and what replaces it is
  /// the answer.
  ///
  /// The two outcome sounds are the ones iOS itself uses for a card that
  /// was read and a card that was not, taken from the system sound
  /// library by name (``UISoundLibrary``), so a ReFineID hold sounds
  /// like every other card operation on the phone. Haptics are
  /// `UINotificationFeedbackGenerator`, likewise the system's own.
  ///
  /// Both obey the phone's switches: a silenced phone plays nothing, and
  /// a phone with system haptics off feels nothing. The haptic is why
  /// there are two channels -- it still fires on a silenced phone, so a
  /// failed hold is never completely quiet.
  @MainActor
  internal enum CardPrimingFeedback {
    /// The repeating tick, running while the hold is.
    private static var ticking: Task<Void, Never>?

    /// The camera's countdown tick.
    ///
    /// Written to repeat, unlike the keyboard tock, which becomes a
    /// rattle after four of them.
    private static let workingSoundName = "camera_timer_countdown"

    /// The pling iOS plays when a card read completes.
    ///
    /// The sound the holder already knows means the card was read.
    private static let successSoundName = "nfc_scan_complete"

    /// The tone iOS plays when a card read does not complete.
    ///
    /// The whole point of this one: it is the system's own sound for a
    /// card that did not work, so it reaches a holder who has already
    /// looked away and been shown Apple's checkmark.
    private static let failureSoundName = "nfc_scan_failure"

    /// The keyboard tock, if the countdown tick is not on this system.
    private static let workingFallbackID: SystemSoundID = 1_104

    /// The bright tink, if the NFC pling is not on this system.
    private static let successFallbackID: SystemSoundID = 1_057

    /// The blunt alert tone, if the NFC failure tone is not.
    private static let failureFallbackID: SystemSoundID = 1_073

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
          AudioServicesPlaySystemSound(
            UISoundLibrary.soundID(
              named: Self.workingSoundName, fallback: Self.workingFallbackID))
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
      AudioServicesPlaySystemSound(
        succeeded
          ? UISoundLibrary.soundID(
            named: Self.successSoundName, fallback: Self.successFallbackID)
          : UISoundLibrary.soundID(
            named: Self.failureSoundName, fallback: Self.failureFallbackID))
    }

    /// Ends the tick without saying anything about the outcome.
    internal static func stopWorking() {
      Self.ticking?.cancel()
      Self.ticking = nil
    }
  }

#endif
