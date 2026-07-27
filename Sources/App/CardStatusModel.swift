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
  ///
  /// It reads, and it changes nothing. A refresh briefly dropped "stale"
  /// token registrations, on the reasoning that a holder pressing
  /// refresh wants the thing to start working rather than to be read
  /// again -- and it destroyed the working card. The system keeps a
  /// configuration for every token it has, including the live one, so
  /// "everything except our own credential entry" is not a description
  /// of stale registrations: it includes the token Safari is using. The
  /// screen unregistered the card it was reporting on, then reported it
  /// missing, seconds after a successful login.
  ///
  /// Whatever recovery this app offers has to identify a dead
  /// registration by something other than not being ours.
  internal func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    snapshot = await CardStatusSnapshot.capture()
    isRefreshing = false
  }
}
