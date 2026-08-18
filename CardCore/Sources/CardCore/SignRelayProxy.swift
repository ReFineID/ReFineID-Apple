// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Answers a paired requester's card requests, at most once each.
///
/// The card's retry counter does not go back up, so a request that arrives
/// twice must reach the card once. The answer is kept under the request's
/// identifier and replayed if the same identifier is asked again, which is
/// the whole of what at-most-once needs here.
public actor SignRelayProxy {
  /// Performs one request against the card.
  public typealias Perform = @Sendable (PersistentRelayMessage) async -> PersistentRelayMessage

  private let channel: any SignRelayChannel
  private let perform: Perform
  private var answered: [UUID: PersistentRelayMessage] = [:]
  private var running: Set<UUID> = []

  /// Serves requests over `channel`, performing each with `perform`.
  public init(channel: any SignRelayChannel, perform: @escaping Perform) {
    self.channel = channel
    self.perform = perform
  }

  /// Handles one frame and answers with the frame to send back, if any.
  ///
  /// A frame that will not open ends the session; the caller closes and the
  /// pairing is untouched. A request already in flight is ignored rather
  /// than started a second time.
  public func receive(_ frame: Data) async throws -> Data? {
    let request = try PersistentRelayMessage.decoded(try channel.open(frame))
    let id = request.requestID
    if let answer = answered[id] {
      return try channel.seal(try answer.encoded())
    }
    guard !running.contains(id) else { return nil }
    running.insert(id)
    let answer = await perform(request)
    running.remove(id)
    answered[id] = answer
    return try channel.seal(try answer.encoded())
  }
}
