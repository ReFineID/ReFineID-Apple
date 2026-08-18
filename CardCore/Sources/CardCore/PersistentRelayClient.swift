// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(MultipeerConnectivity)
  @preconcurrency import MultipeerConnectivity
  import os

  /// One synchronous request bridge for CryptoTokenKit's synchronous sign
  /// callback.
  ///
  /// A client object is intentionally single-use.
  public final class PersistentRelayClient: @unchecked Sendable {
    private struct State: Sendable {
      var completed = false
      var request: PersistentRelayMessage?
      var response: PersistentRelayMessage?
      var error: PersistentRelayTransportError?
    }

    private let displayName: String
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let completed = DispatchSemaphore(value: 0)
    private lazy var session = PersistentRelaySession(
      role: .host,
      displayName: displayName
    ) { [weak self] event in
      self?.receive(event)
    }

    /// Names the local peer; the channel starts on ``perform(_:timeout:)``.
    public init(displayName: String) {
      self.displayName = displayName
    }

    /// Sends one request and blocks for its correlated answer.
    public func perform(
      _ request: PersistentRelayMessage,
      timeout: TimeInterval = 120
    ) throws -> PersistentRelayMessage {
      let accepted = state.withLock { state -> Bool in
        guard state.request == nil else { return false }
        state.request = request
        return true
      }
      guard accepted else {
        throw PersistentRelayTransportError.send("client is single-use")
      }
      session.start()
      guard completed.wait(timeout: .now() + timeout) == .success else {
        session.cancel()
        throw PersistentRelayTransportError.timedOut
      }
      session.cancel()
      return try state.withLock { state in
        if let response = state.response { return response }
        throw state.error ?? PersistentRelayTransportError.disconnected
      }
    }

    private func receive(_ event: PersistentRelayEvent) {
      switch event {
      case .connected:
        guard let request = state.withLock({ $0.request }) else { return }
        do {
          try session.send(try request.encoded())
        } catch let error as PersistentRelayTransportError {
          finish(error: error)
        } catch {
          finish(error: .send(String(describing: error)))
        }
      case .frame(let frame):
        do {
          let message = try PersistentRelayMessage.decoded(frame)
          guard
            let requestID = state.withLock({ $0.request?.requestID }),
            requestID == message.requestID
          else { return }
          finish(response: message)
        } catch {
          finish(error: .codec(String(describing: error)))
        }
      case .closed(let error):
        finish(error: error)
      }
    }

    private func finish(
      response: PersistentRelayMessage? = nil,
      error: PersistentRelayTransportError? = nil
    ) {
      let shouldSignal = state.withLock { state -> Bool in
        guard !state.completed else { return false }
        state.completed = true
        state.response = response
        state.error = error
        return true
      }
      if shouldSignal { completed.signal() }
    }
  }
#endif
