// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// Session component state.
///
/// A session instance exists per connection attempt; `absent` means no live
/// instance for the pairing, and `closed` is terminal for the instance.
internal enum SessionState: String, CaseIterable, Sendable {
  case absent
  /// Requester only.
  case connecting
  case authenticating
  case healthy
  case checking
  case closing
  case closed

  /// Whether the session can still carry authenticated traffic.
  internal var carriesAuthenticatedTraffic: Bool {
    switch self {
    case .healthy, .checking:
      true
    case .absent, .connecting, .authenticating, .closing, .closed:
      false
    }
  }
}

// swiftlint:enable sorted_enum_cases
