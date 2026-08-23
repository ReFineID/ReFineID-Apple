// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import RappEngine
  import SwiftUI

  #if os(iOS)
    import UIKit
  #elseif os(macOS)
    import AppKit
  #endif

  @MainActor
  internal final class RappPairingModel: ObservableObject {
    internal enum Phase: Equatable {
      case idle
      case offer(String)
      case codeEntry
      case connecting
      case paired(RappPairingCoordinator.PairSummary)
      case failed(String)
    }

    private enum Policy {
      /// RAPP 0.1 OFFER_TTL_MAX.
      static let offerLifetimeMilliseconds: UInt64 = 180_000

      /// Names the one stream candidate an offer of this transport carries.
      static let streamCandidateID = "stream-1"
    }

    /// The in-protocol name the reviewing peer sees for this requester.
    private static var requesterDisplayName: String {
      #if os(macOS)
        Host.current().localizedName ?? String(localized: "Mac")
      #else
        UIDevice.current.name
      #endif
    }

    /// The in-protocol platform name for this requester.
    private static var requesterPlatform: String {
      #if os(macOS)
        "macOS"
      #else
        "iOS"
      #endif
    }

    /// The one transport candidate an offer carries, by build.
    ///
    /// The stream candidate names no endpoints: the holder publishes a
    /// listener under a name derived from this offer, and the requester
    /// finds it there.
    internal static var offeredCandidate: RappPairingCoordinator.TransportCandidate {
      #if REFINEID_STREAM_TRANSPORT
        .init(
          profile: rappStreamProfileName(),
          candidateID: Policy.streamCandidateID,
          parametersCBOR: RappApplePeerProfile.candidateParameters
        )
      #else
        .init(
          profile: RappApplePeerProfile.name,
          candidateID: RappApplePeerProfile.candidateID,
          parametersCBOR: RappApplePeerProfile.candidateParameters
        )
      #endif
    }

    @Published internal var phase = Phase.idle
    @Published internal private(set) var pairs: [RappPairingCoordinator.PairSummary] = []
    @Published internal var selectedPairID: Data?
    @Published internal var pairingCode: String?

    internal let vault: RappDeviceVault
    internal let catalog: RappPairCatalog
    internal var relay: PairingRelay?
    internal var relayGeneration: UUID?
    internal var coordinator: RappPairingCoordinator?
    internal var eventTask: Task<Void, Never>?
    internal var reviewedPeerName: String?

    /// Ceremony events enter the coordinator in arrival order through
    /// this bounded chain; reset between attempts.
    private let eventDelivery = OrderedDelivery(
      capacity: OrderedDelivery.relayFrameCapacity)

    internal var isFinished: Bool {
      switch phase {
      case .paired, .failed:
        true
      case .idle, .offer, .codeEntry, .connecting:
        false
      }
    }

    internal init(vault: RappDeviceVault = RappDeviceVault()) {
      self.vault = vault
      self.catalog = RappPairCatalog(vault: vault)
    }

    internal func refresh() {
      Task {
        do {
          pairs = try await catalog.activePairs()
          selectedPairID = try await catalog.selectedPair()?.pairID
        } catch {
          pairs = []
          selectedPairID = nil
        }
      }
    }

    internal func createOffer() {
      createOffer(customCode: nil)
    }

    internal func createOffer(customCode: String?) {
      resetAttempt()
      #if REFINEID_LOCAL_CARD && os(iOS)
        PhonePersistentTokenRelay.shared.suspendForPairing()
      #endif
      let code = customCode.map(RappPairingCode.normalize) ?? RappPairingCode.generate()
      pairingCode = code
      #if DEBUG
        print("[pairing] generated code: \(code)")
      #endif
      let relay = makeRelay(role: .host)
      let transport = makeTransport(relay: relay)
      publish(
        code: code,
        candidates: [Self.offeredCandidate],
        selectedCandidateID: Self.offeredCandidate.candidateID,
        relay: relay,
        transport: transport
      )
    }

    /// Makes the offer the 8-character code and candidates describe and shows its code.
    internal func publish(
      code: String,
      candidates: [RappPairingCoordinator.TransportCandidate],
      selectedCandidateID: String,
      relay: PairingRelay,
      transport: any RappFrameTransport
    ) {
      do {
        let coordinator = try RappPairingCoordinator.requester(
          profiles: RappApplePeerProfile.supportedCredentialProfiles,
          candidates: candidates,
          selectedCandidateID: selectedCandidateID,
          offerLifetimeMilliseconds: Policy.offerLifetimeMilliseconds,
          displayName: Self.requesterDisplayName,
          platform: Self.requesterPlatform,
          vault: vault,
          transport: transport,
          code: code
        )
        install(coordinator: coordinator, relay: relay)
        Task { [weak self] in
          await coordinator.publishOffer()
          guard let self, self.coordinator === coordinator, !isFinished,
            let uri = coordinator.offerURI
          else { return }
          #if DEBUG
            print("[pairing] setting phase to .offer with code: \(code)")
            print("[pairing] URI is: \(uri)")
          #endif
          phase = .offer(code)
          relay.start(sharingOfferURI: uri)
        }
      } catch {
        fail(String(localized: "Pairing could not be started"))
      }
    }

    internal func cancel() {
      let coordinator = coordinator
      relay?.cancel()
      finishAttempt()
      phase = .idle
      Task { await coordinator?.close() }
      resumeRegularRelay()
    }

    internal func makeRelay(role: PersistentRelayRole) -> PairingRelay {
      let generation = UUID()
      relayGeneration = generation
      let displayName: String
      switch role {
      case .host:
        #if os(macOS)
          displayName = String(localized: "ReFineID Mac")
        #else
          displayName = String(localized: "ReFineID iPad")
        #endif
      case .cardHolder:
        displayName = String(localized: "ReFineID iPhone")
      }
      return PairingRelay(
        role: role,
        displayName: displayName
      ) { [weak self] event in
        Task { @MainActor in self?.receive(event, generation: generation) }
      }
    }

    internal func makeTransport(
      relay: PairingRelay
    ) -> RappClosureFrameTransport {
      RappClosureFrameTransport(
        sender: { [weak relay] frame in
          guard let relay else {
            throw PersistentRelayTransportError.disconnected
          }
          try await relay.send(frame)
        },
        closer: { [weak relay] in relay?.cancel() }
      )
    }

    internal func install(
      coordinator: RappPairingCoordinator,
      relay: PairingRelay
    ) {
      self.coordinator = coordinator
      self.relay = relay
      eventTask = Task { [weak self] in
        for await event in coordinator.events {
          self?.receive(event, from: coordinator)
        }
      }
    }

    private func receive(
      _ event: PersistentRelayEvent,
      generation: UUID
    ) {
      guard generation == relayGeneration else { return }
      guard let coordinator else { return }
      switch event {
      case .connected:
        deliverInOrder { await coordinator.transportConnected() }
      case .frame(let frame):
        deliverInOrder { await coordinator.receive(frame) }
      case .closed:
        guard !isFinished else {
          finishAttempt()
          return
        }
        deliverInOrder { await coordinator.transportClosed() }
      }
    }

    /// Runs `work` after every delivery enqueued before it; a peer that
    /// outruns the bounded chain ends the attempt.
    private func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
      if eventDelivery.deliver(work) { return }
      relay?.cancel()
    }

    internal func fail(_ message: String) {
      let coordinator = coordinator
      phase = .failed(message)
      relay?.cancel()
      finishAttempt()
      Task { await coordinator?.close() }
      resumeRegularRelay()
    }

    internal func finishAttempt() {
      relay = nil
      relayGeneration = nil
      coordinator = nil
      eventTask?.cancel()
      eventTask = nil
      eventDelivery.reset()
    }

    internal func resetAttempt() {
      let coordinator = coordinator
      relay?.cancel()
      finishAttempt()
      phase = .idle
      Task { await coordinator?.close() }
    }

    internal func resumeRegularRelay() {
      #if REFINEID_LOCAL_CARD && os(iOS)
        PhonePersistentTokenRelay.shared.resumeAfterUserAction()
      #endif
    }
  }
#endif
