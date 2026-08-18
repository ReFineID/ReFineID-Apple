// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Asks a paired card holder for one card operation and waits for its answer.
///
/// The wait is bounded by a deadline rather than by probing the peer: over a
/// channel that authenticates every frame, a peer that answers has proved it
/// is there, and a peer that does not is indistinguishable from one that
/// cannot reach the card. Both mean the same thing to the holder.
public actor SignRelayRequester {
  /// Why a request produced no answer.
  public enum Failure: Error, Equatable {
    /// Nothing arrived before the deadline.
    case timedOut

    /// The peer's answer did not match the request.
    case mismatched

    /// The frame did not open, so the session is over.
    case sessionEnded
  }

  private let channel: any SignRelayChannel
  private var pending: [UUID: CheckedContinuation<PersistentRelayMessage, Error>] = [:]

  /// Asks over `channel`.
  public init(channel: any SignRelayChannel) {
    self.channel = channel
  }

  /// Sends `request` and answers when its correlated reply arrives.
  ///
  /// - Parameters:
  ///   - request: the card operation to ask for.
  ///   - timeout: how long to wait before giving up on the peer.
  ///   - send: hands the sealed frame to the transport.
  /// - Returns: the peer's reply, correlated to this request.
  /// - Throws: ``Failure/timedOut`` when nothing arrives in time, and
  ///   ``Failure/sessionEnded`` when a frame will not open.
  public func perform(
    _ request: PersistentRelayMessage,
    timeout: Duration,
    send: (Data) async throws -> Void
  ) async throws -> PersistentRelayMessage {
    let id = request.requestID
    try await send(try channel.seal(try request.encoded()))
    let deadline = Task { [weak self] in
      try? await Task.sleep(for: timeout)
      await self?.expire(id)
    }
    defer { deadline.cancel() }
    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
    }
  }

  /// Hands one received frame to whichever request it answers.
  public func receive(_ frame: Data) throws {
    let answer: PersistentRelayMessage
    do {
      answer = try PersistentRelayMessage.decoded(try channel.open(frame))
    } catch {
      failAll(with: Failure.sessionEnded)
      throw Failure.sessionEnded
    }
    guard let continuation = pending.removeValue(forKey: answer.requestID) else { return }
    continuation.resume(returning: answer)
  }

  /// Ends every wait, because the session did.
  public func failAll(with failure: Failure) {
    let waiting = pending
    pending.removeAll()
    for continuation in waiting.values {
      continuation.resume(throwing: failure)
    }
  }

  private func expire(_ id: UUID) {
    guard let continuation = pending.removeValue(forKey: id) else { return }
    continuation.resume(throwing: Failure.timedOut)
  }
}
