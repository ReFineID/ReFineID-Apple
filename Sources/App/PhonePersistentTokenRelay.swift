// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import Network
  import RappEngine
  /// Owns the phone side of one mutually authenticated RAPP connection.
  ///
  /// The transport is an opaque frame carrier chosen by the selected pair:
  /// MultipeerConnectivity advertises nearby, while the stream profile dials
  /// the requester's stored listener endpoints. All identity, sequencing,
  /// operation, and fail-stop decisions belong to RAPP.
  #if DEBUG
    /// The event's case name alone, which is what a timeline needs.
    private func eventCaseName(_ event: RappConnectionCoordinator.Event) -> String {
      String(describing: event).prefix { $0 != "(" }.description
    }
  #endif

  @MainActor
  internal final class PhonePersistentTokenRelay {

    // MARK: Nested Types

    internal enum RelistenPolicy {
      case automatic
      case explicitUserActionRequired
    }

    // MARK: Static Properties

    internal static let shared = PhonePersistentTokenRelay()

    internal static let maximumPreCoordinatorFrames = 4
    /// Pause between stream dial attempts while redialing is automatic.
    internal static let streamRedialDelayMilliseconds = 2_000

    // MARK: Properties

    internal let vault = RappDeviceVault()
    private let policy = RappRequesterPolicy.interactive
    internal var relay: PersistentRelaySession?
    #if REFINEID_STREAM_TRANSPORT
      internal var streamListener: StreamRelayListener?
      internal var streamContext: PhoneStreamPairContext?
    #endif
    internal var coordinator: RappConnectionCoordinator?
    #if REFINEID_SLIM_RELAY
      private var slimSession: SignRelaySession?
      private var slimProxy: SignRelayProxy?
    #endif
    internal var dispatcher: RappPhoneProxyDispatcher?
    internal var connectionID: UUID?
    internal var preCoordinatorFrames: [Data] = []
    internal var relistenPolicy = RelistenPolicy.automatic

    // MARK: Lifecycle

    private init() {}

    // MARK: Functions

    internal func start() {
      // A proxy without an antenna is not a proxy: only near-field
      // devices advertise as the card holder.
      guard SupportedCardTransports.offersNearField else { return }
      guard relay == nil, coordinator == nil,
        relistenPolicy == .automatic,
        hasUsableSelectedPair()
      else { return }

      #if REFINEID_STREAM_TRANSPORT
        guard streamListener == nil else { return }
        guard let context = PhoneStreamPairContext.resolve(vault: vault) else { return }
        startListening(context)
      #else
        let nearbyConnectionID = UUID()
        let nearby = PersistentRelaySession(
          role: .cardHolder,
          displayName: "ReFineID iPhone"
        ) { [weak self] event in
          Task { @MainActor in
            self?.receive(event, connectionID: nearbyConnectionID)
          }
        }
        connectionID = nearbyConnectionID
        relay = nearby
        nearby.start()
      #endif
    }

    /// Explicit UI action may call this after the user has corrected local
    /// credentials or deliberately chosen to reconnect.
    ///
    /// It never restores a revoked pair; the vault remains authoritative.
    internal func resumeAfterUserAction() {
      relistenPolicy = .automatic
      if relay == nil, coordinator == nil { start() }
    }

    internal func suspendForPairing() {
      relistenPolicy = .explicitUserActionRequired
      let closing = coordinator
      relay?.cancel()
      #if REFINEID_STREAM_TRANSPORT
        streamListener?.cancel()
      #endif
      Task { await closing?.close() }
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

    /// Tears down the closed connection and reconnects while automatic,
    /// yielding immediately for the nearby relay and pausing between
    /// stream dial attempts.
    internal func handleTransportClosed(redialDelayMilliseconds: Int) {
      let closingCoordinator = coordinator
      coordinator = nil
      dispatcher = nil
      relay = nil
      #if REFINEID_STREAM_TRANSPORT
        streamListener = nil
        streamContext = nil
      #endif
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

    internal func establishCoordinator(
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
      #if DEBUG
        HolderTrace.say("session event \(eventCaseName(event))")
      #endif
      if PhoneRelayFailStops.requireExplicitUserAction(event) {
        relistenPolicy = .explicitUserActionRequired
      }
    }

    private func requireExplicitUserAction() {
      relistenPolicy = .explicitUserActionRequired
    }

    internal func hasUsableSelectedPair() -> Bool {
      (try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault)) != nil
    }
  }
#endif
