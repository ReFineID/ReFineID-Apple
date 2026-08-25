// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_STREAM_TRANSPORT && REFINEID_REMOTE_CARD
  import CardCore
  import Foundation
  import RappEngine

  /// The stream transport's half of the phone relay.
  ///
  /// The holder is the side whose listener every peer can reach, so it
  /// publishes under the selected pair's derived name and waits; the
  /// requester finds the name and dials with the pair's session preamble.
  @MainActor
  extension PhonePersistentTokenRelay {
    /// Listens under the selected pair's derived name and waits for the
    /// requester to dial.
    ///
    /// The requester opens with the pair's session preamble; that frame is
    /// the arrival, not a message, and says which pairing the dial is for.
    internal func startListening(_ context: PhoneStreamPairContext) {
      #if DEBUG
        print("[stream-holder] listening as \(context.serviceName)")
        fflush(stdout)
      #endif
      let listeningConnectionID = UUID()
      connectionID = listeningConnectionID
      streamContext = context
      let listener = StreamRelayListener { [weak self] event in
        Task { @MainActor in
          self?.receiveStream(event, connectionID: listeningConnectionID)
        }
      }
      streamListener = listener
      listener.start(displayName: context.serviceName)
    }

    private func receiveStream(
      _ event: StreamRelayEvent,
      connectionID: UUID
    ) {
      guard self.connectionID == connectionID else { return }
      switch event {
      case .connected:
        // A connection is not yet this pair's requester: the session
        // preamble is.
        #if DEBUG
          print("[stream-holder] a dialer arrived")
          fflush(stdout)
        #endif

      case .frame(let frame):
        #if DEBUG
          let expected = streamContext?.sessionPreamble.count ?? 0
          print(
            "[stream-holder] frame \(frame.count) bytes, preamble \(expected), "
              + "match \(frame == streamContext?.sessionPreamble), "
              + "session \(coordinator != nil)")
          fflush(stdout)
        #endif
        if let matched = matchedPair(forPreamble: frame) {
          establishStream(connectionID: connectionID, pair: matched)
        } else if let coordinator {
          deliverInOrder { await coordinator.receive(frame) }
        } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
          preCoordinatorFrames.append(frame)
        } else {
          streamListener?.cancel()
        }

      case .closed:
        handleTransportClosed(
          redialDelayMilliseconds: Self.streamRedialDelayMilliseconds
        )
      }
    }

    private func matchedPair(forPreamble frame: Data) -> RappPairRecord? {
      if frame == streamContext?.sessionPreamble,
        let pair = try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault)
      {
        return pair
      }
      guard let activeIDs = try? vault.activePairIDs() else { return nil }
      for pairID in activeIDs {
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault) else {
          continue
        }
        if let preamble = try? rappStreamSessionPreamble(
          rendezvousToken: pair.metadata().rendezvousToken
        ), frame == preamble {
          return pair
        }
      }
      return nil
    }

    private func establishStream(connectionID: UUID, pair: RappPairRecord) {
      guard self.connectionID == connectionID, coordinator == nil,
        let streamListener
      else { return }

      let transport = RappClosureFrameTransport(
        sender: { [weak streamListener] frame in
          guard let streamListener else {
            throw StreamRelayTransportError.notConnected
          }
          try streamListener.send(frame)
        },
        closer: { [weak streamListener] in streamListener?.cancel() }
      )
      establishCoordinator(
        connectionID: connectionID,
        pair: pair,
        transport: transport
      ) { [weak streamListener] in
        streamListener?.cancel()
      }
    }
  }
#endif
