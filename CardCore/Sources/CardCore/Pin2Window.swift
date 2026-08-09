import Foundation

/// PIN2, held for a few seconds so a batch is one prompt.
///
/// The card's rule is unchanged and cannot be changed: it verifies PIN2
/// immediately before every qualified signature. What this decides is
/// only where the value comes from each time -- from the holder, or
/// from the entry the holder just made. Signing twelve documents meant
/// twelve identical prompts, which is not security, it is a person
/// typing the same digits twelve times and reading none of them.
///
/// The window is deliberately short. It is measured from the entry, not
/// extended by use, so a batch that runs long asks again rather than
/// stretching one authorization indefinitely.
///
/// What it never does: reach disk, reach a log, outlive the session
/// that holds it, or satisfy anything but a qualified signature. PIN1
/// has its own path and the two are never interchangeable.
public struct Pin2Window {
  /// How long an entry stays usable.
  ///
  /// Long enough for a batch of documents, short enough that a card
  /// left in a reader is not a signing service for the rest of the
  /// afternoon.
  public static let lifetime: TimeInterval = 60

  private var value: String?
  private var enteredAt: Date?

  /// A window with nothing in it.
  public init() {
    // Both fields start empty; nothing is held until an entry is made.
  }

  /// Records an entry, starting the window.
  public mutating func hold(_ pin: String) {
    guard !pin.isEmpty else {
      forget()
      return
    }
    value = pin
    enteredAt = Date()
  }

  /// The entry, if one was made and the window has not closed.
  ///
  /// Reading does not extend it: the window belongs to the entry.
  public mutating func current(now: Date = Date()) -> String? {
    guard let value, let enteredAt else { return nil }
    guard now.timeIntervalSince(enteredAt) < Self.lifetime else {
      forget()
      return nil
    }
    return value
  }

  /// Drops the entry.
  ///
  /// On a refusal, on a card leaving, on anything unexpected. Cheap to
  /// call, and the safe thing to do when in doubt.
  public mutating func forget() {
    value = nil
    enteredAt = nil
  }
}
