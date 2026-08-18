// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

/// A channel that seals by prefixing and refuses anything else.
///
/// Noise is a proven primitive and is not what these tests are about; what
/// they are about is everything that was layered on top of it.
internal struct SignRelayMarkerChannel: SignRelayChannel {
  /// What a sealed frame begins with.
  internal static let marker = Data("sealed:".utf8)

  internal func seal(_ payload: Data) -> Data {
    Self.marker + payload
  }

  internal func open(_ frame: Data) throws -> Data {
    guard frame.starts(with: Self.marker) else {
      throw SignRelayRequester.Failure.sessionEnded
    }
    return frame.dropFirst(Self.marker.count)
  }
}
