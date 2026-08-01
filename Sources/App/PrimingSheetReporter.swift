#if canImport(CoreNFC) && os(iOS)

  import Foundation

  /// Keeps the running step states and repaints the NFC sheet from them.
  ///
  /// Every step change and every sentence go through here, so the sheet
  /// always shows the whole meter rather than whichever half was written
  /// most recently. The card work runs on its own queue and the steps
  /// are reported from there, so the states live behind a lock.
  ///
  /// `@unchecked Sendable` is the audit: the dictionary is touched only
  /// under the lock, and the session it draws into is itself safe to
  /// update from any thread.
  @available(iOS 26.0, *)
  internal final class PrimingSheetReporter: @unchecked Sendable {
    /// The hold this meter is drawn on, so a caller needing the card
    /// does not have to be handed the session separately.
    internal let session: NearFieldCardSession

    private let lock = NSLock()
    private var states: [CardPrimingStep: CardPrimingStep.State] = [:]
    private var activity: String

    internal init(session: NearFieldCardSession, activity: String) {
      self.session = session
      self.activity = activity
    }

    /// Records a step's state and repaints.
    internal func report(_ step: CardPrimingStep, _ state: CardPrimingStep.State) {
      lock.lock()
      states[step] = state
      let snapshot = states
      let sentence = activity
      lock.unlock()
      session.update(message: PrimingSheetMessage.line(states: snapshot, activity: sentence))
    }

    /// Replaces the sentence under the meter and repaints.
    ///
    /// The meter is unchanged: what the holder is being told changed,
    /// not how far the run got.
    internal func say(_ sentence: String) {
      lock.lock()
      activity = sentence
      let snapshot = states
      lock.unlock()
      session.update(message: PrimingSheetMessage.line(states: snapshot, activity: sentence))
    }

    /// Marks every step that never ran as failed, and says why.
    ///
    /// A hold that breaks at PACE leaves three steps that never started,
    /// and leaving them as empty balls reads as still to come on a sheet
    /// that is about to dismiss. The step that broke keeps its cross;
    /// the rest are crossed too, because none of them happened.
    internal func fail(_ sentence: String) {
      lock.lock()
      for step in CardPrimingStep.allCases where states[step] != .done {
        states[step] = .failed
      }
      activity = sentence
      let snapshot = states
      lock.unlock()
      session.update(message: PrimingSheetMessage.line(states: snapshot, activity: sentence))
    }
  }

#endif
