import CardCore
import Observation

/// Holds the latest status snapshot for the UI; refreshes are manual or
/// event-driven, never periodic.
@MainActor
@Observable
internal final class CardStatusModel {
  /// The latest capture, or nil before the first refresh completes.
  internal private(set) var snapshot: CardStatusSnapshot?

  /// True while a capture is running.
  internal private(set) var isRefreshing = false

  /// How many stale registrations the last refresh dropped, when it
  /// dropped any -- worth saying, because it explains a card that
  /// started working without the holder doing anything.
  internal private(set) var droppedRegistrations: Int?

  /// Captures a fresh snapshot unless one is already in flight.
  ///
  /// A refresh clears stale token registrations first. Reading the state
  /// again is not what a holder means by "refresh" when the state is
  /// wrong: what they want is for it to start working, and the one thing
  /// this app can do about that is drop the registrations the system is
  /// holding for cards that have come and gone.
  internal func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    #if os(macOS)
      let dropped = await Task.detached(priority: .userInitiated) {
        DriverConfiguredCredentials.dropStaleTokenConfigurations()
      }.value
      if dropped > 0 {
        droppedRegistrations = dropped
      }
    #endif
    snapshot = await CardStatusSnapshot.capture()
    isRefreshing = false
  }
}
