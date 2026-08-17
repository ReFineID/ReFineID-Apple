// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && canImport(CoreNFC)
  import CardCore
  import Foundation
  import Observation
  import ReFineIDRapp

  /// Owns the phone side of the one live RAPP pairing.
  ///
  /// The pairing UI runs the ceremony and hands the authenticated channel
  /// over; from then on this holder pumps its card operations until the
  /// connection closes. Every close is terminal: the pairing ends with its
  /// connection, and a new pairing requires a fresh QR scan.
  @MainActor
  @Observable
  internal final class PhonePersistentTokenRelay {
    internal static let shared = PhonePersistentTokenRelay()

    /// The live pairing shown to the holder while its connection lasts.
    internal struct LivePairing: Equatable {
      internal let summary: RappPairingCoordinator.PairSummary
      internal let peerName: String?
    }

    internal private(set) var livePairing: LivePairing?

    @ObservationIgnored private let vault = RappDeviceVault()
    @ObservationIgnored private let policy = RappRequesterPolicy.interactive
    @ObservationIgnored private var coordinator: RappConnectionCoordinator?
    @ObservationIgnored private var dispatcher: RappPhoneProxyDispatcher?
    @ObservationIgnored private var channelRetention: AnyObject?
    @ObservationIgnored private var frameQueue: [Data] = []
    @ObservationIgnored private var draining = false
    @ObservationIgnored private var coordinatorStarted = false
    @ObservationIgnored private var adoptionPending = false
    @ObservationIgnored private var generation = UUID()

    private init() {
      // The one process-wide holder; connections arrive by adoption.
    }

    /// The reviewed requester's name for the live pairing.
    internal var livePeerName: String? { livePairing?.peerName }

    /// Enters the handover window: the previous connection ends and frames
    /// arriving before ``completeAdoption`` are buffered in order.
    internal func beginAdoption() {
      endConnection()
      adoptionPending = true
    }

    /// Abandons a handover whose channel could not be taken over.
    internal func abandonAdoption() {
      guard adoptionPending else { return }
      endConnection()
    }

    /// Adopts the completed pairing's live channel from the pairing UI.
    ///
    /// The relay object is retained so the transport closure keeps a
    /// target; frames buffered during the handover are replayed in order
    /// before newly arriving ones.
    internal func completeAdoption(
      pairing: RappPairingBridge,
      transport: any RappFrameTransport,
      summary: RappPairingCoordinator.PairSummary,
      peerName: String?,
      retaining channel: AnyObject?
    ) {
      guard adoptionPending else {
        Task { await transport.close() }
        return
      }
      adoptionPending = false
      let adoptionGeneration = UUID()
      generation = adoptionGeneration
      do {
        let coordinator = try RappConnectionCoordinator(
          role: .proxy,
          pairing: pairing,
          vault: vault,
          transport: transport,
          maximumLifetimeMilliseconds:
            policy.maximumOperationLifetimeMilliseconds,
          liveness: policy.liveness
        )
        let dispatcher = RappPhoneProxyDispatcher(
          inbox: RappAuthorizationInbox.shared
        )
        self.coordinator = coordinator
        self.dispatcher = dispatcher
        self.channelRetention = channel
        self.livePairing = LivePairing(summary: summary, peerName: peerName)
        Task { [weak self] in
          for await event in coordinator.events {
            await dispatcher.receive(event, from: coordinator)
            self?.observe(event, generation: adoptionGeneration)
          }
        }
        Task { [weak self] in
          await coordinator.start()
          self?.beginDraining(generation: adoptionGeneration)
        }
      } catch {
        endConnection()
        Task { await transport.close() }
      }
    }

    /// One frame from the adopted relay, in arrival order.
    internal func receiveAdoptedFrame(_ frame: Data) {
      guard adoptionPending || coordinator != nil else { return }
      frameQueue.append(frame)
      drainIfPossible()
    }

    /// The adopted relay closed underneath the session.
    internal func adoptedTransportClosed() {
      guard !adoptionPending else {
        endConnection()
        return
      }
      let coordinator = coordinator
      Task { await coordinator?.transportClosed() }
    }

    /// Ends the live pairing at the holder's request.
    internal func endLivePairing() {
      endConnection()
    }

    private func beginDraining(generation: UUID) {
      guard self.generation == generation else { return }
      coordinatorStarted = true
      drainIfPossible()
    }

    private func drainIfPossible() {
      guard coordinatorStarted, !draining, coordinator != nil,
        !frameQueue.isEmpty
      else { return }
      draining = true
      Task { @MainActor in
        while let coordinator = self.coordinator, !self.frameQueue.isEmpty {
          let next = self.frameQueue.removeFirst()
          await coordinator.receive(next)
        }
        self.draining = false
      }
    }

    private func observe(
      _ event: RappConnectionCoordinator.Event,
      generation: UUID
    ) {
      guard self.generation == generation else { return }
      if case .closed = event {
        endConnection()
      }
    }

    private func endConnection() {
      let coordinator = coordinator
      self.coordinator = nil
      dispatcher = nil
      channelRetention = nil
      frameQueue.removeAll(keepingCapacity: false)
      draining = false
      coordinatorStarted = false
      adoptionPending = false
      livePairing = nil
      generation = UUID()
      Task { await coordinator?.close() }
    }
  }
#endif
