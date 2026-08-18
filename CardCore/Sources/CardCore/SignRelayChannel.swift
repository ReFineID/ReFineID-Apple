// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Seals and opens the payloads of one session.
///
/// The session's cipher already refuses a replayed, reordered or skipped
/// frame, because each direction advances a nonce per frame and a frame out
/// of place will not decrypt. Nothing above this needs to say so a second
/// time, and a second statement of the same rule can only disagree with the
/// first by being wrong.
public protocol SignRelayChannel: Sendable {
  /// Seals one payload for the peer.
  func seal(_ payload: Data) throws -> Data

  /// Opens one frame from the peer.
  ///
  /// - Throws: when the frame does not decrypt, which ends the session and
  ///   leaves the pairing standing.
  func open(_ frame: Data) throws -> Data
}
