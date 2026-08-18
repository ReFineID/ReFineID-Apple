#if canImport(RappEngine)
  import Foundation
  import RappEngine
  /// Drives one explicit, one-use RAPP pairing attempt. No pair secret is exposed
  /// to Swift; the generated Rust bridge owns the QR bearer secret, Noise state,
  /// private keys, transcript checks, and final pair record.
  public actor RappPairingCoordinator {
    /// One transport option offered for the pairing attempt.
    public struct TransportCandidate: Sendable, Equatable {
      /// Registered transport profile name.
      public let profile: String
      /// Opaque identifier echoed back after peer authentication.
      public let candidateID: String
      /// Deterministic-CBOR map of profile-specific public parameters.
      public let parametersCBOR: Data

      fileprivate var binding: RappTransportCandidate {
        RappTransportCandidate(
          profile: profile,
          candidateId: candidateID,
          parametersCbor: parametersCBOR
        )
      }

      /// Creates a candidate from already-encoded public parameters.
      public init(profile: String, candidateID: String, parametersCBOR: Data) {
        self.profile = profile
        self.candidateID = candidateID
        self.parametersCBOR = parametersCBOR
      }
    }

    /// Authenticated peer facts shown for the explicit pairing decision.
    public struct Peer: Sendable, Equatable {
      /// User-visible peer label shown during pairing confirmation.
      public let displayName: String
      /// Peer platform label.
      public let platform: String
      /// Exact requester profile list; absent when the peer is the proxy.
      public let requestedProfiles: [String]?

      fileprivate init(_ hello: RappPeerHello) {
        displayName = hello.displayName
        platform = hello.platform
        requestedProfiles = hello.requestedProfiles
      }
    }

    /// Non-secret metadata for a completed pairing.
    public struct PairSummary: Sendable, Equatable {
      /// Local endpoint role bound into the pair record.
      public enum Role: Sendable, Equatable {
        case requester
        case proxy
      }

      /// Transcript-derived pair identifier.
      public let pairID: Data
      /// Local role permanently bound into the pair record.
      public let role: Role
      /// Exact mutually confirmed profile names.
      public let profiles: [String]
      /// Transport profile bound into the pair.
      public let transportProfile: String
      /// Transport candidate identifier bound into the pair.
      public let candidateID: String
      /// Wall-clock creation time recorded in the pair record.
      public let createdAtMilliseconds: UInt64

      init(_ metadata: RappPairMetadata) {
        pairID = metadata.pairId
        role = metadata.role == .requester ? .requester : .proxy
        profiles = metadata.profiles
        transportProfile = metadata.transportProfile
        candidateID = metadata.candidateId
        createdAtMilliseconds = metadata.createdAtMs
      }
    }

    /// Reason the pairing attempt ended without a completed pair.
    public enum CloseReason: Sendable, Equatable {
      case denied
      case localRequest
      case transportFailure
      case protocolFailure
      case persistenceFailure
      case offerExpired
    }

    /// One externally visible pairing event.
    public enum Event: Sendable, Equatable {
      /// Secret-bearing text intended only for a QR renderer. It must never be
      /// logged, persisted, copied to analytics, or synchronized.
      case offerReady(uri: String)
      /// The same unconsumed requester offer is ready after an
      /// unauthenticated candidate failed. A fresh transport is required.
      case offerRestored(uri: String)
      case reviewPeer(Peer)
      case paired(PairSummary)
      case closed(CloseReason)
    }

    private enum Role {
      case requester
      case proxy
    }

    private enum State: Equatable {
      case offer
      case awaitingRequesterHandshake
      case awaitingResponderHandshake
      case awaitingFinalRequesterHandshake
      case awaitingPeerHello
      case awaitingLocalDecision
      case awaitingPeerConfirmation
      case completed
      case closed
    }

    /// Delivers pairing events in order until the attempt ends.
    nonisolated public let events: AsyncStream<Event>
    /// Secret-bearing QR text; present only for the requester role.
    nonisolated public let offerURI: String?

    private let role: Role
    private let bridge: RappPairingBridge
    private let vault: RappDeviceVault
    private var transport: any RappFrameTransport
    private let candidateID: String
    private let displayName: String
    private let platform: String
    private let clock: RappPlatformClock
    private let offerDeadlineMilliseconds: UInt64
    private let continuation: AsyncStream<Event>.Continuation
    private var state = State.offer
    private var peer: Peer?
    private var peerGrantedProfiles: [String]?
    private var localConfirmationSent = false
    private var offerExpiryTask: Task<Void, Never>?

    private init(
      role: Role,
      bridge: RappPairingBridge,
      offerURI: String?,
      selectedCandidateID: String,
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      clock: RappPlatformClock,
      offerDeadlineMilliseconds: UInt64
    ) {
      self.role = role
      self.bridge = bridge
      self.offerURI = offerURI
      self.candidateID = selectedCandidateID
      self.displayName = displayName
      self.platform = platform
      self.vault = vault
      self.transport = transport
      self.clock = clock
      self.offerDeadlineMilliseconds = offerDeadlineMilliseconds

      var capturedContinuation: AsyncStream<Event>.Continuation?
      self.events = AsyncStream { capturedContinuation = $0 }
      guard let capturedContinuation else {
        preconditionFailure("AsyncStream did not provide a continuation")
      }
      self.continuation = capturedContinuation
    }

    private static func deadline(startedAt: UInt64, lifetime: UInt64) -> UInt64 {
      let (deadline, overflow) = startedAt.addingReportingOverflow(lifetime)
      return overflow ? UInt64.max : deadline
    }

    /// Creates the requester side owning a fresh one-use offer that covers
    /// the given transport candidates.
    public static func requester(
      profiles: [String],
      candidates: [TransportCandidate],
      selectedCandidateID: String,
      offerLifetimeMilliseconds: UInt64,
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      entropy: RappPlatformEntropy = RappPlatformEntropy(),
      clock: RappPlatformClock = RappPlatformClock()
    ) throws -> RappPairingCoordinator {
      let startedAtMonotonicMilliseconds = clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.createRequesterOffer(
        offerId: entropy.offerID(),
        pairingSecret: entropy.pairingSecret(),
        profiles: profiles,
        transports: candidates.map(\.binding),
        offerTtlMs: offerLifetimeMilliseconds,
        startedAtMonotonicMs: startedAtMonotonicMilliseconds
      )
      return try RappPairingCoordinator(
        role: .requester,
        bridge: bridge,
        offerURI: bridge.offerUri(nowMonotonicMs: startedAtMonotonicMilliseconds),
        selectedCandidateID: selectedCandidateID,
        displayName: displayName,
        platform: platform,
        vault: vault,
        transport: transport,
        clock: clock,
        offerDeadlineMilliseconds: deadline(
          startedAt: startedAtMonotonicMilliseconds,
          lifetime: offerLifetimeMilliseconds
        )
      )
    }

    /// Creates the proxy side from a scanned requester offer.
    public static func proxy(
      scannedOfferURI: String,
      selectedCandidateID: String,
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      clock: RappPlatformClock = RappPlatformClock()
    ) throws -> RappPairingCoordinator {
      let startedAtMonotonicMilliseconds = clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.fromScannedOffer(
        uri: scannedOfferURI,
        startedAtMonotonicMs: startedAtMonotonicMilliseconds
      )
      return try RappPairingCoordinator(
        role: .proxy,
        bridge: bridge,
        offerURI: nil,
        selectedCandidateID: selectedCandidateID,
        displayName: displayName,
        platform: platform,
        vault: vault,
        transport: transport,
        clock: clock,
        offerDeadlineMilliseconds: deadline(
          startedAt: startedAtMonotonicMilliseconds,
          lifetime: try bridge.offerTtlMs()
        )
      )
    }

    /// Publishes the requester QR without consuming it or starting transport.
    public func publishOffer() {
      guard state == .offer, let offerURI else { return }
      continuation.yield(.offerReady(uri: offerURI))
      scheduleOfferExpiry()
    }

    /// Installs the transport for the next candidate after the requester
    /// retained its still-live offer.
    ///
    /// Replacement is legal only while the coordinator projects `offer_active`.
    @discardableResult
    public func replaceTransport(_ replacement: any RappFrameTransport) -> Bool {
      guard state == .offer else { return false }
      transport = replacement
      return true
    }

    /// Consumes the offer only after the selected candidate is connected.
    public func transportConnected() async {
      guard state == .offer else {
        await fail(.protocolFailure)
        return
      }
      scheduleOfferExpiry()
      do {
        try bridge.begin(
          candidateId: candidateID,
          nowMonotonicMs: clock.monotonicMilliseconds()
        )
        switch role {
        case .requester:
          let frame = try bridge.writeHandshakeFrame(
            nowMonotonicMs: clock.monotonicMilliseconds()
          )
          state = .awaitingResponderHandshake
          try await transport.send(frame)
        case .proxy:
          state = .awaitingRequesterHandshake
        }
      } catch RappBindingError.OfferExpired {
        await fail(.offerExpired)
      } catch {
        await recoverOrFail(.transportFailure, closeCandidate: true)
      }
    }

    /// Consumes one complete opaque frame received from the transport.
    public func receive(_ frame: Data) async {
      do {
        switch state {
        case .awaitingRequesterHandshake:
          try bridge.readHandshakeFrame(
            bytes: frame,
            nowMonotonicMs: clock.monotonicMilliseconds()
          )
          let response = try bridge.writeHandshakeFrame(
            nowMonotonicMs: clock.monotonicMilliseconds()
          )
          state = .awaitingFinalRequesterHandshake
          try await transport.send(response)

        case .awaitingResponderHandshake:
          try bridge.readHandshakeFrame(
            bytes: frame,
            nowMonotonicMs: clock.monotonicMilliseconds()
          )
          let finalHandshake = try bridge.writeHandshakeFrame(
            nowMonotonicMs: clock.monotonicMilliseconds()
          )
          guard
            try bridge.handshakeComplete(
              nowMonotonicMs: clock.monotonicMilliseconds()
            )
          else {
            await recoverOrFail(.protocolFailure, closeCandidate: true)
            return
          }
          try bridge.enterConfirmation(
            nowMonotonicMs: clock.monotonicMilliseconds()
          )
          offerExpiryTask?.cancel()
          offerExpiryTask = nil
          let hello = try bridge.sendHello(displayName: displayName, platform: platform)
          state = .awaitingPeerHello
          try await transport.send(finalHandshake)
          try await transport.send(hello)

        case .awaitingFinalRequesterHandshake:
          try bridge.readHandshakeFrame(
            bytes: frame,
            nowMonotonicMs: clock.monotonicMilliseconds()
          )
          guard
            try bridge.handshakeComplete(
              nowMonotonicMs: clock.monotonicMilliseconds()
            )
          else {
            await recoverOrFail(.protocolFailure, closeCandidate: true)
            return
          }
          try bridge.enterConfirmation(
            nowMonotonicMs: clock.monotonicMilliseconds()
          )
          offerExpiryTask?.cancel()
          offerExpiryTask = nil
          let hello = try bridge.sendHello(displayName: displayName, platform: platform)
          state = .awaitingPeerHello
          try await transport.send(hello)

        case .awaitingPeerHello:
          let received = try bridge.receiveHello(
            bytes: frame,
            nowMs: clock.wallMilliseconds()
          )
          let peer = Peer(received)
          self.peer = peer
          state = .awaitingLocalDecision
          continuation.yield(.reviewPeer(peer))

        case .awaitingLocalDecision:
          peerGrantedProfiles = try bridge.receiveConfirmation(
            bytes: frame,
            nowMs: clock.wallMilliseconds()
          )

        case .awaitingPeerConfirmation:
          peerGrantedProfiles = try bridge.receiveConfirmation(
            bytes: frame,
            nowMs: clock.wallMilliseconds()
          )
          try await finishIfMutuallyConfirmed()

        case .offer, .completed, .closed:
          await fail(.protocolFailure)
        }
      } catch RappBindingError.OfferExpired {
        await fail(.offerExpired)
      } catch {
        await recoverOrFail(.protocolFailure, closeCandidate: true)
      }
    }

    /// Sends the exact user-approved grant set.
    ///
    /// Pair persistence remains impossible until the authenticated peer grant
    /// has also arrived.
    public func approve(grantedProfiles: [String]) async {
      guard state == .awaitingLocalDecision, peer != nil else {
        await fail(.protocolFailure)
        return
      }
      do {
        let frame = try bridge.sendConfirmation(grantedProfiles: grantedProfiles)
        try await transport.send(frame)
        localConfirmationSent = true
        if peerGrantedProfiles == nil {
          state = .awaitingPeerConfirmation
        } else {
          try await finishIfMutuallyConfirmed()
        }
      } catch {
        await fail(.protocolFailure)
      }
    }

    /// Denies the reviewed peer and ends the attempt without a pair.
    public func deny() async {
      guard state == .awaitingLocalDecision else { return }
      await fail(.denied)
    }

    /// Reacts to transport closure, restoring the requester offer when legal.
    public func transportClosed() async {
      switch state {
      case .offer:
        return
      case .awaitingRequesterHandshake,
        .awaitingResponderHandshake,
        .awaitingFinalRequesterHandshake:
        await recoverOrFail(.transportFailure, closeCandidate: false)
      case .awaitingPeerHello,
        .awaitingLocalDecision,
        .awaitingPeerConfirmation,
        .completed,
        .closed:
        await fail(.transportFailure)
      }
    }

    /// Ends the pairing attempt at local request.
    public func close() async {
      await fail(.localRequest)
    }

    private func finishIfMutuallyConfirmed() async throws {
      guard localConfirmationSent, peerGrantedProfiles != nil else {
        return
      }
      let record = try bridge.finishPairing(createdAtMs: clock.wallMilliseconds())
      do {
        try record.persistDeviceOnly(vault: vault)
        let summary = PairSummary(try record.metadata())
        state = .completed
        offerExpiryTask?.cancel()
        offerExpiryTask = nil
        continuation.yield(.paired(summary))
        continuation.finish()
        await transport.close()
      } catch {
        await fail(.persistenceFailure)
      }
    }

    private func fail(_ reason: CloseReason) async {
      guard state != .closed, state != .completed else { return }
      state = .closed
      offerExpiryTask?.cancel()
      offerExpiryTask = nil
      try? bridge.cancelPairing()
      await transport.close()
      continuation.yield(.closed(reason))
      continuation.finish()
    }

    private func recoverOrFail(
      _ terminalReason: CloseReason,
      closeCandidate: Bool
    ) async {
      do {
        if try await restoreRequesterOffer(closeCandidate: closeCandidate) {
          return
        }
      } catch RappBindingError.OfferExpired {
        await fail(.offerExpired)
        return
      } catch {
        // A state that cannot expose the original live offer is terminal.
      }
      await fail(terminalReason)
    }

    private func restoreRequesterOffer(closeCandidate: Bool) async throws -> Bool {
      guard case .requester = role else { return false }
      let now = clock.monotonicMilliseconds()
      switch state {
      case .offer:
        break
      case .awaitingRequesterHandshake,
        .awaitingResponderHandshake,
        .awaitingFinalRequesterHandshake:
        do {
          guard try bridge.candidateFailed(nowMonotonicMs: now) else {
            return false
          }
        } catch RappBindingError.WrongPhase {
          // Frame processing already restored the offer atomically.
        }
      case .awaitingPeerHello,
        .awaitingLocalDecision,
        .awaitingPeerConfirmation,
        .completed,
        .closed:
        return false
      }
      let uri = try bridge.offerUri(nowMonotonicMs: now)
      state = .offer
      if closeCandidate {
        await transport.close()
      }
      continuation.yield(.offerRestored(uri: uri))
      scheduleOfferExpiry()
      return true
    }

    private func scheduleOfferExpiry() {
      guard offerExpiryTask == nil else { return }
      let now = clock.monotonicMilliseconds()
      let remainingMilliseconds =
        offerDeadlineMilliseconds > now
        ? offerDeadlineMilliseconds - now
        : 0
      let (nanoseconds, overflow) = remainingMilliseconds.multipliedReportingOverflow(
        by: 1_000_000
      )
      let delay = overflow ? UInt64.max : nanoseconds
      offerExpiryTask = Task { [weak self] in
        do {
          try await Task.sleep(nanoseconds: delay)
        } catch {
          return
        }
        guard !Task.isCancelled, let self else { return }
        await expireOffer()
      }
    }

    private func expireOffer() async {
      guard
        state == .offer
          || state == .awaitingRequesterHandshake
          || state == .awaitingResponderHandshake
          || state == .awaitingFinalRequesterHandshake
      else { return }
      await fail(.offerExpired)
    }

    deinit {
      offerExpiryTask?.cancel()
      continuation.finish()
    }
  }
#endif
