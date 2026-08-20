// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine
  /// Owns the phone side of one mutually authenticated RAPP connection.
  ///
  /// The transport is an opaque frame carrier chosen by the selected pair:
  /// MultipeerConnectivity advertises nearby, while the stream profile dials
  /// the requester's stored listener endpoints. All identity, sequencing,
  /// operation, and fail-stop decisions belong to RAPP.
  @MainActor
  internal final class PhonePersistentTokenRelay {

    // MARK: Nested Types

    private enum RelistenPolicy {
      case automatic
      case explicitUserActionRequired
    }

    // MARK: Static Properties

    internal static let shared = PhonePersistentTokenRelay()

    private static let maximumPreCoordinatorFrames = 4
    /// Pause between stream dial attempts while redialing is automatic.
    private static let streamRedialDelayMilliseconds = 2_000

    // MARK: Properties

    private let vault = RappDeviceVault()
    private let policy = RappRequesterPolicy.interactive
    private var relay: PersistentRelaySession?
    private var streamRelay: StreamRelaySession?
    private var coordinator: RappConnectionCoordinator?
    #if REFINEID_SLIM_RELAY
      private var slimSession: SignRelaySession?
      private var slimProxy: SignRelayProxy?
    #endif
    private var dispatcher: RappPhoneProxyDispatcher?
    private var connectionID: UUID?
    private var preCoordinatorFrames: [Data] = []
    private var relistenPolicy = RelistenPolicy.automatic

    // MARK: Lifecycle

    private init() {}

    // MARK: Functions

    internal func start() {
      // A proxy without an antenna is not a proxy: only near-field
      // devices advertise as the card holder.
      guard SupportedCardTransports.offersNearField else { return }
      guard relay == nil, streamRelay == nil, coordinator == nil,
        relistenPolicy == .automatic,
        hasUsableSelectedPair()
      else { return }

      if let context = PhoneStreamPairContext.resolve(vault: vault) {
        startStream(context)
        return
      }

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
    /// credentials or deliberately chosen to reconnect.
    ///
    /// It never restores a revoked pair; the vault remains authoritative.
    internal func resumeAfterUserAction() {
      relistenPolicy = .automatic
      if relay == nil, streamRelay == nil, coordinator == nil { start() }
    }

    internal func suspendForPairing() {
      relistenPolicy = .explicitUserActionRequired
      let coordinator = coordinator
      relay?.cancel()
      streamRelay?.cancel()
      Task { await coordinator?.close() }
    }

    /// The stream profile dials the requester's stored listener endpoints
    /// with the pair's session preamble instead of advertising nearby.
    private func startStream(_ context: PhoneStreamPairContext) {
      let streamConnectionID = UUID()
      let stream = StreamRelaySession(
        endpointLiterals: context.endpoints,
        preamble: context.preamble
      ) { [weak self] event in
        Task { @MainActor in
          self?.receiveStream(event, connectionID: streamConnectionID)
        }
      }
      connectionID = streamConnectionID
      streamRelay = stream
      stream.start()
    }

    private func receive(
      _ event: PersistentRelayEvent,
      connectionID: UUID
    ) {
      guard self.connectionID == connectionID else { return }
      switch event {
      case .connected:
        establish(connectionID: connectionID)

      case .frame(let frame):
        #if REFINEID_SLIM_RELAY
          if slimSession != nil {
            Task { await receiveSlim(frame) }
            return
          }
        #endif
        if let coordinator {
          Task { await coordinator.receive(frame) }
        } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
          preCoordinatorFrames.append(frame)
        } else {
          relay?.cancel()
        }

      case .closed:
        handleTransportClosed(redialDelayMilliseconds: 0)
      }
    }

    private func receiveStream(
      _ event: StreamRelayEvent,
      connectionID: UUID
    ) {
      guard self.connectionID == connectionID else { return }
      switch event {
      case .connected:
        establishStream(connectionID: connectionID)

      case .frame(let frame):
        if let coordinator {
          Task { await coordinator.receive(frame) }
        } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
          preCoordinatorFrames.append(frame)
        } else {
          streamRelay?.cancel()
        }

      case .closed:
        handleTransportClosed(
          redialDelayMilliseconds: Self.streamRedialDelayMilliseconds
        )
      }
    }

    /// Tears down the closed connection and reconnects while automatic,
    /// yielding immediately for the nearby relay and pausing between
    /// stream dial attempts.
    private func handleTransportClosed(redialDelayMilliseconds: Int) {
      let closingCoordinator = coordinator
      coordinator = nil
      dispatcher = nil
      relay = nil
      streamRelay = nil
      connectionID = nil
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      Task { await closingCoordinator?.transportClosed() }
      if !hasUsableSelectedPair() {
        relistenPolicy = .explicitUserActionRequired
      }
      guard relistenPolicy == .automatic else { return }
      Task { @MainActor in
        if redialDelayMilliseconds > 0 {
          try? await Task.sleep(for: .milliseconds(redialDelayMilliseconds))
        } else {
          await Task.yield()
        }
        self.start()
      }
    }

    private func establish(connectionID: UUID) {
      guard self.connectionID == connectionID, coordinator == nil,
        let relay
      else { return }

      let transport = RappClosureFrameTransport(
        sender: { [weak relay] frame in
          guard let relay else {
            throw PersistentRelayTransportError.disconnected
          }
          try relay.send(frame)
        },
        closer: { [weak relay] in relay?.cancel() }
      )
      establishCoordinator(
        connectionID: connectionID,
        transport: transport
      ) { [weak relay] in
        relay?.cancel()
      }
    }

    private func establishStream(connectionID: UUID) {
      guard self.connectionID == connectionID, coordinator == nil,
        let streamRelay
      else { return }

      let transport = RappClosureFrameTransport(
        sender: { [weak streamRelay] frame in
          guard let streamRelay else {
            throw StreamRelayTransportError.notConnected
          }
          try await streamRelay.send(frame)
        },
        closer: { [weak streamRelay] in streamRelay?.cancel() }
      )
      establishCoordinator(
        connectionID: connectionID,
        transport: transport
      ) { [weak streamRelay] in
        streamRelay?.cancel()
      }
    }

    #if REFINEID_SLIM_RELAY
      /// Serves the slim relay over the selected pairing.
      private func establishSlim(
        pair: RappPairRecord,
        transport: RappClosureFrameTransport
      ) throws {
        let session = try SignRelaySession(role: .proxy, pair: pair, vault: vault)
        slimSession = session
        let journal = (try? vault.selectedPairID()).flatMap { pairID in
          pairID.map { SignRelayVaultJournal(vault: vault, pairID: $0) }
        }
        slimProxy = SignRelayProxy(journal: journal) { request in
          #if REFINEID_LOCAL_CARD
            return await SlimCardWork.perform(request)
          #else
            // A device with no card path can serve nobody else's request.
            return .failure(id: request.requestID, reason: .cardUnavailable)
          #endif
        }
        _ = transport
      }

      /// Drives one frame through the slim session and answers what it asks.
      private func receiveSlim(_ frame: Data) async {
        guard let session = slimSession, let proxy = slimProxy else { return }
        let step: SignRelayStep
        do {
          step = try await session.receive(frame)
        } catch {
          relay?.cancel()
          return
        }
        for outgoing in step.send {
          try? relay?.send(outgoing)
        }
        guard let payload = step.payload else { return }
        guard let answer = try? await proxy.answer(to: payload) else { return }
        guard let sealed = try? await session.seal(answer) else { return }
        try? relay?.send(sealed)
      }
    #endif

    private func establishCoordinator(
      connectionID: UUID,
      transport: RappClosureFrameTransport,
      failTransport: () -> Void
    ) {
      do {
        guard
          let pair = try PhoneProxyPairSelection.resolveSelectedPair(
            vault: vault
          )
        else {
          relistenPolicy = .explicitUserActionRequired
          failTransport()
          return
        }
        #if REFINEID_SLIM_RELAY
          try establishSlim(pair: pair, transport: transport)
        #else
          let made = try RappConnectionCoordinator(
            role: .proxy,
            pair: pair,
            vault: vault,
            transport: transport,
            maximumLifetimeMilliseconds:
              policy.maximumOperationLifetimeMilliseconds,
            liveness: policy.liveness
          )
          let madeDispatcher = RappPhoneProxyDispatcher(
            inbox: RappAuthorizationInbox.shared
          ) { [weak self] in
            self?.requireExplicitUserAction()
          }
          coordinator = made
          dispatcher = madeDispatcher

          let earlyFrames = preCoordinatorFrames
          preCoordinatorFrames.removeAll(keepingCapacity: false)
          Task { [weak self] in
            for await event in made.events {
              await madeDispatcher.receive(event, from: made)
              self?.observe(event, connectionID: connectionID)
            }
          }
          Task {
            await made.start()
            for frame in earlyFrames {
              await made.receive(frame)
            }
          }
        #endif
      } catch {
        relistenPolicy = .explicitUserActionRequired
        failTransport()
      }
    }

    private func observe(
      _ event: RappConnectionCoordinator.Event,
      connectionID: UUID
    ) {
      guard self.connectionID == connectionID else { return }
      if PhoneRelayFailStops.requireExplicitUserAction(event) {
        relistenPolicy = .explicitUserActionRequired
      }
    }

    private func requireExplicitUserAction() {
      relistenPolicy = .explicitUserActionRequired
    }

    private func hasUsableSelectedPair() -> Bool {
      (try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault)) != nil
    }
  }
#endif
