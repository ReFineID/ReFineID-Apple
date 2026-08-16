// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && canImport(CoreNFC)
  import CardCore
  import Foundation
  import ReFineIDRapp

    /// Owns the phone side of one mutually authenticated RAPP connection.
    /// MultipeerConnectivity remains an opaque frame carrier; all identity,
    /// sequencing, operation, and fail-stop decisions belong to RAPP.
    @MainActor
    internal final class PhonePersistentTokenRelay {
      internal static let shared = PhonePersistentTokenRelay()

      private enum RelistenPolicy {
        case automatic
        case explicitUserActionRequired
      }

      private static let maximumPreCoordinatorFrames = 4

      private let vault = RappDeviceVault()
      private let policy = RappRequesterPolicy.interactive
      private var relay: PersistentRelaySession?
      private var coordinator: RappConnectionCoordinator?
      private var dispatcher: RappPhoneProxyDispatcher?
      private var connectionID: UUID?
      private var preCoordinatorFrames: [Data] = []
      private var relistenPolicy = RelistenPolicy.automatic

      private init() {}

      internal func start() {
        guard relay == nil, coordinator == nil,
          relistenPolicy == .automatic,
          hasUsableSelectedPair()
        else { return }

        let connectionID = UUID()
        let relay = PersistentRelaySession(
          role: .cardHolder,
          displayName: "ReFineID iPhone"
        ) { [weak self] event in
          Task { @MainActor in
            self?.receive(event, connectionID: connectionID)
          }
        }
        self.connectionID = connectionID
        self.relay = relay
        relay.start()
      }

      /// Explicit UI action may call this after the user has corrected local
      /// credentials or deliberately chosen to reconnect. It never restores a
      /// revoked pair; the vault remains authoritative.
      internal func resumeAfterUserAction() {
        relistenPolicy = .automatic
        if relay == nil, coordinator == nil { start() }
      }

      internal func suspendForPairing() {
        relistenPolicy = .explicitUserActionRequired
        let coordinator = coordinator
        relay?.cancel()
        Task { await coordinator?.close() }
      }

      private func receive(
        _ event: PersistentRelayEvent,
        connectionID: UUID
      ) {
        guard self.connectionID == connectionID else { return }
        switch event {
        case .connected:
          establish(connectionID: connectionID)

        case let .frame(frame):
          if let coordinator {
            Task { await coordinator.receive(frame) }
          } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
            preCoordinatorFrames.append(frame)
          } else {
            relay?.cancel()
          }

        case .closed:
          let coordinator = coordinator
          self.coordinator = nil
          dispatcher = nil
          relay = nil
          self.connectionID = nil
          preCoordinatorFrames.removeAll(keepingCapacity: false)
          Task { await coordinator?.transportClosed() }
          if !hasUsableSelectedPair() {
            relistenPolicy = .explicitUserActionRequired
          }
          guard relistenPolicy == .automatic else { return }
          Task { @MainActor in
            await Task.yield()
            self.start()
          }
        }
      }

      private func establish(connectionID: UUID) {
        guard self.connectionID == connectionID, coordinator == nil,
          let relay
        else { return }

        do {
          let pairIDs = try vault.activePairIDs()
          guard !pairIDs.isEmpty else {
            relistenPolicy = .explicitUserActionRequired
            relay.cancel()
            return
          }
          let pairID: Data
          if let selected = try vault.selectedPairID() {
            guard pairIDs.contains(selected) else {
              try vault.clearSelectedPair()
              relistenPolicy = .explicitUserActionRequired
              relay.cancel()
              return
            }
            pairID = selected
          } else if pairIDs.count == 1 {
            pairID = pairIDs[0]
            try vault.selectPair(pairID: pairID)
          } else {
            relistenPolicy = .explicitUserActionRequired
            relay.cancel()
            return
          }
          let pair = try RappPairRecord.loadFromVault(
            pairId: pairID,
            vault: vault
          )
          let transport = RappClosureFrameTransport(
            sender: { [weak relay] frame in
              guard let relay else {
                throw PersistentRelayTransportError.disconnected
              }
              try relay.send(frame)
            },
            closer: { [weak relay] in relay?.cancel() }
          )
          let coordinator = try RappConnectionCoordinator(
            role: .proxy,
            pair: pair,
            vault: vault,
            transport: transport,
            maximumLifetimeMilliseconds:
              policy.maximumOperationLifetimeMilliseconds,
            liveness: policy.liveness
          )
          let dispatcher = RappPhoneProxyDispatcher(
            inbox: RappAuthorizationInbox.shared,
            requireExplicitReconnect: { [weak self] in
              self?.requireExplicitUserAction()
            }
          )
          self.coordinator = coordinator
          self.dispatcher = dispatcher

          let earlyFrames = preCoordinatorFrames
          preCoordinatorFrames.removeAll(keepingCapacity: false)
          Task { [weak self] in
            for await event in coordinator.events {
              await dispatcher.receive(event, from: coordinator)
              self?.observe(event, connectionID: connectionID)
            }
          }
          Task {
            await coordinator.start()
            for frame in earlyFrames {
              await coordinator.receive(frame)
            }
          }
        } catch {
          relistenPolicy = .explicitUserActionRequired
          relay.cancel()
        }
      }

      private func observe(
        _ event: RappConnectionCoordinator.Event,
        connectionID: UUID
      ) {
        guard self.connectionID == connectionID else { return }
        switch event {
        case let .terminal(_, _, reason):
          switch reason {
          case .credentialRejected, .cardCompletionAmbiguous:
            relistenPolicy = .explicitUserActionRequired
          case .userDenied, .requestExpired, .cancelled,
               .requestInvalidOrUnsupported, .retryPolicyRefused,
               .cardRemovedBeforeTransmit, nil:
            break
          }

        case let .closed(reason):
          switch reason {
          case .handshake(.protocolFailure), .handshake(.pairRevoked),
               .operation(.protocolFailure), .operation(.pairRevoked):
            relistenPolicy = .explicitUserActionRequired
          case .handshake(.localRequest), .handshake(.transportClosed),
               .operation(.localRequest), .operation(.transportClosed),
               .operation(.terminalFrameReleased), .transportFailure,
               .localRequest:
            break
          }

        case .established, .inspectPrerequisites, .awaitUserApproval,
             .executeSafeRead, .executeCardCommand, .completed,
             .advisoryCancellation, .operationFinished, .peerBusy,
             .peerUnknownOperation:
          break
        }
      }

      private func requireExplicitUserAction() {
        relistenPolicy = .explicitUserActionRequired
      }

      private func hasUsableSelectedPair() -> Bool {
        guard
          let pairIDs = try? vault.activePairIDs(),
          !pairIDs.isEmpty
        else { return false }
        if let selected = try? vault.selectedPairID() {
          return pairIDs.contains(selected)
        }
        guard pairIDs.count == 1 else { return false }
        do {
          try vault.selectPair(pairID: pairIDs[0])
          return true
        } catch {
          return false
        }
      }
    }
#endif
