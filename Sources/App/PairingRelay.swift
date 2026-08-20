// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

#if REFINEID_STREAM_TRANSPORT
  import Network
#endif

/// The channel a pairing ceremony runs over, whichever transport carries it.
///
/// Pairing and the sessions that follow it have to travel the same way: a
/// pairing made over a transport the peers cannot use again is a pairing
/// they cannot use. This presents one shape so the ceremony does not know
/// which is underneath.
internal final class PairingRelay: @unchecked Sendable {
  private let onEvent: @Sendable (PersistentRelayEvent) -> Void

  #if REFINEID_STREAM_TRANSPORT
    private let role: PersistentRelayRole
    private let displayName: String
    private var listener: StreamRelayListener?
    private var browser: StreamRelayBrowser?
    private var dialer: StreamRelaySession?
  #else
    private let session: PersistentRelaySession
  #endif

  /// Builds the channel one side of a ceremony speaks over.
  internal init(
    role: PersistentRelayRole,
    displayName: String,
    onEvent: @escaping @Sendable (PersistentRelayEvent) -> Void
  ) {
    self.onEvent = onEvent
    #if REFINEID_STREAM_TRANSPORT
      self.role = role
      self.displayName = displayName
    #else
      self.session = PersistentRelaySession(
        role: role,
        displayName: displayName,
        onEvent: onEvent
      )
    #endif
  }

  /// Opens the channel.
  internal func start() {
    #if REFINEID_STREAM_TRANSPORT
      switch role {
      case .host:
        let made = StreamRelayListener { [weak self] event in
          self?.receiveStream(event)
        }
        listener = made
        made.start(displayName: displayName)
      case .cardHolder:
        let found = StreamRelayBrowser { [weak self] endpoint in
          self?.dial(endpoint)
        }
        browser = found
        found.start()
      }
    #else
      session.start()
    #endif
  }

  /// Hands one frame to the peer.
  internal func send(_ frame: Data) async throws {
    #if REFINEID_STREAM_TRANSPORT
      switch role {
      case .host:
        guard let listener else { throw PersistentRelayTransportError.disconnected }
        try listener.send(frame)
      case .cardHolder:
        guard let dialer else { throw PersistentRelayTransportError.disconnected }
        try await dialer.send(frame)
      }
    #else
      try session.send(frame)
    #endif
  }

  /// Closes the channel.
  internal func cancel() {
    #if REFINEID_STREAM_TRANSPORT
      listener?.cancel()
      browser?.cancel()
      dialer?.cancel()
    #else
      session.cancel()
    #endif
  }

  #if REFINEID_STREAM_TRANSPORT
    /// Dials the requester once its published listener has been found.
    private func dial(_ endpoint: NWEndpoint) {
      guard dialer == nil else { return }
      let made = StreamRelaySession(
        service: endpoint,
        preamble: StreamRelayPreamble.hello
      ) { [weak self] event in
        self?.receiveStream(event)
      }
      dialer = made
      made.start()
    }

    /// Reports a stream event the way the ceremony above names it.
    ///
    /// The dialer's announcing frame is the arrival itself and carries no
    /// message, so it is never passed up.
    private func receiveStream(_ event: StreamRelayEvent) {
      if case .frame(let payload) = event, payload == StreamRelayPreamble.hello {
        onEvent(.connected)
        return
      }
      onEvent(PersistentRelayEvent(event))
    }
  #endif
}
