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

  /// Captures a fresh snapshot unless one is already in flight.
  internal func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    snapshot = await CardStatusSnapshot.capture()
    isRefreshing = false
  }
}
