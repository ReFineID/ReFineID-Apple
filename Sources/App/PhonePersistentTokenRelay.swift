// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_REMOTE_CARD
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
    /// How long the stream transport pauses before re-listening after a
    /// connection closes.
    internal static let streamRedialDelayMilliseconds = 100

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
      internal var slimSession: SignRelaySession?
      internal var slimProxy: SignRelayProxy?
    #endif
    internal var dispatcher: RappPhoneProxyDispatcher?
    internal var connectionID: UUID?
    internal var preCoordinatorFrames: [Data] = []
    internal var relistenPolicy = RelistenPolicy.automatic

    /// Frames enter the coordinator in arrival order through this
    /// bounded chain; reset between connections.
    internal let frameDelivery = OrderedDelivery(
      capacity: OrderedDelivery.relayFrameCapacity)

    // MARK: Lifecycle

    private init() {
      // singleton
    }

    // MARK: Functions

    internal func start() {
      // A proxy without an antenna is not a proxy: only near-field
      // devices advertise as the card holder.
      guard SupportedCardTransports.offersNearField else { return }
      #if REFINEID_STREAM_TRANSPORT
        guard streamListener == nil, coordinator == nil,
          relistenPolicy == .automatic,
          hasUsableSelectedPair()
        else { return }
        guard let context = PhoneStreamPairContext.resolve(vault: vault) else { return }
        startListening(context)
      #else
        guard relay == nil, coordinator == nil,
          relistenPolicy == .automatic,
          hasUsableSelectedPair()
        else { return }
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
      #if REFINEID_STREAM_TRANSPORT
        if streamListener == nil, coordinator == nil { start() }
      #else
        if relay == nil, coordinator == nil { start() }
      #endif
    }

    internal func suspendForPairing() {
      relistenPolicy = .explicitUserActionRequired
      let closing = coordinator
      coordinator = nil
      relay?.cancel()
      relay = nil
      #if REFINEID_STREAM_TRANSPORT
        streamListener?.cancel()
        streamListener = nil
        streamContext = nil
      #endif
      connectionID = nil
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
            deliverInOrder { [weak self] in
              // The delivery may outlive the connection it belongs to;
              // a frame for a gone connection must not touch the next
              // one's session.
              guard let self, await self.connectionID == connectionID else { return }
              await receiveSlim(frame)
            }
            return
          }
        #endif
        if let coordinator {
          deliverInOrder { await coordinator.receive(frame) }
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
      frameDelivery.reset()
      #if REFINEID_SLIM_RELAY
        slimSession = nil
        slimProxy = nil
      #endif
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
          // The replay joins the same chain later frames append to, so a
          // frame arriving during the replay cannot overtake it.
          deliverInOrder {
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

    /// Runs `work` after every delivery enqueued before it, cancelling a
    /// transport whose peer outruns the bounded chain.
    internal func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
      if frameDelivery.deliver(work) { return }
      relay?.cancel()
      #if REFINEID_STREAM_TRANSPORT
        streamListener?.cancel()
      #endif
    }

    internal func hasUsableSelectedPair() -> Bool {
      (try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault)) != nil
    }
  }
#endif
