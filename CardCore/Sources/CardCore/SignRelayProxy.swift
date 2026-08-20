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
  private let journal: (any SignRelayJournal)?
  private var answered: [UUID: PersistentRelayMessage] = [:]
  private var running: Set<UUID> = []

  /// Serves requests over `channel`, performing each with `perform`.
  ///
  /// - Parameters:
  ///   - channel: seals and opens this session's frames.
  ///   - journal: where answers outlive the process; without one they last
  ///     only as long as this proxy does.
  ///   - perform: reaches the card.
  public init(
    channel: any SignRelayChannel,
    journal: (any SignRelayJournal)? = nil,
    perform: @escaping Perform
  ) {
    self.channel = channel
    self.journal = journal
    self.perform = perform
  }

  /// Handles one frame and answers with the frame to send back, if any.
  ///
  /// A frame that will not open ends the session; the caller closes and the
  /// pairing is untouched. A request already in flight is ignored rather
  /// than started a second time.
  ///
  /// - Parameter frame: the bytes the transport delivered.
  /// - Returns: the frame to send back, or nil when the request is already
  ///   being performed.
  /// - Throws: when the frame does not open, or the answer cannot be sealed.
  public func receive(_ frame: Data) async throws -> Data? {
    let request = try PersistentRelayMessage.decoded(try channel.open(frame))
    let id = request.requestID
    if let answer = try alreadyAnswered(id) {
      return try channel.seal(try answer.encoded())
    }
    guard !running.contains(id) else { return nil }
    running.insert(id)
    let answer = await perform(request)
    running.remove(id)
    answered[id] = answer
    try? journal?.record(answer, for: id)
    return try channel.seal(try answer.encoded())
  }

  /// What was already answered for this request, here or in the journal.
  private func alreadyAnswered(_ id: UUID) throws -> PersistentRelayMessage? {
    if let answer = answered[id] { return answer }
    guard let journalled = try journal?.answer(for: id) else { return nil }
    answered[id] = journalled
    return journalled
  }
}
