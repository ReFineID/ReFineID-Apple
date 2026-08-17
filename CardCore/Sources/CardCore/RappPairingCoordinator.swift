#if canImport(ReFineIDRapp)
import Foundation
import ReFineIDRapp

/// Drives one explicit, one-use RAPP pairing attempt. No pair secret is exposed
/// to Swift; the generated Rust bridge owns the QR bearer secret, Noise state,
/// private keys, transcript checks, and final pair record.
public actor RappPairingCoordinator {
    public struct TransportCandidate: Sendable, Equatable {
        public let profile: String
        public let candidateID: String
        public let parametersCBOR: Data

        public init(profile: String, candidateID: String, parametersCBOR: Data) {
            self.profile = profile
            self.candidateID = candidateID
            self.parametersCBOR = parametersCBOR
        }

        fileprivate var binding: RappTransportCandidate {
            RappTransportCandidate(
                profile: profile,
                candidateId: candidateID,
                parametersCbor: parametersCBOR
            )
        }
    }

    public struct Peer: Sendable, Equatable {
        public let displayName: String
        public let platform: String
        public let requestedProfiles: [String]?

        fileprivate init(_ hello: RappPeerHello) {
            displayName = hello.displayName
            platform = hello.platform
            requestedProfiles = hello.requestedProfiles
        }
    }

    public struct PairSummary: Sendable, Equatable {
        public enum Role: Sendable, Equatable {
            case requester
            case proxy
        }

        public let pairID: Data
        public let role: Role
        public let profiles: [String]
        public let transportProfile: String
        public let candidateID: String
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

    public enum CloseReason: Sendable, Equatable {
        case denied
        case localRequest
        case transportFailure
        case protocolFailure
        case persistenceFailure
        case offerExpired
    }

    public enum Event: Sendable, Equatable {
        /// Secret-bearing text intended only for a QR renderer. It must never be
        /// logged, persisted, copied to analytics, or synchronized.
        case offerReady(uri: String)
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

    public nonisolated let events: AsyncStream<Event>
    public nonisolated let offerURI: String?

    private let role: Role
    private let bridge: RappPairingBridge
    private let vault: RappDeviceVault
    private let transport: any RappFrameTransport
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
    ) throws {
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

    deinit {
        offerExpiryTask?.cancel()
        continuation.finish()
    }

    /// Publishes the requester QR without consuming it or starting transport.
    public func publishOffer() {
        guard state == .offer, let offerURI else { return }
        continuation.yield(.offerReady(uri: offerURI))
        scheduleOfferExpiry()
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
            await fail(.transportFailure)
        }
    }

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
                guard try bridge.handshakeComplete(
                    nowMonotonicMs: clock.monotonicMilliseconds()
                ) else {
                    await fail(.protocolFailure)
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
                guard try bridge.handshakeComplete(
                    nowMonotonicMs: clock.monotonicMilliseconds()
                ) else {
                    await fail(.protocolFailure)
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
            await fail(.protocolFailure)
        }
    }

    /// Sends the exact user-approved grant set. Pair persistence remains
    /// impossible until the authenticated peer grant has also arrived.
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

    public func deny() async {
        guard state == .awaitingLocalDecision else { return }
        await fail(.denied)
    }

    public func transportClosed() async {
        await fail(.transportFailure)
    }

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
        await transport.close()
        continuation.yield(.closed(reason))
        continuation.finish()
    }

    private func scheduleOfferExpiry() {
        guard offerExpiryTask == nil else { return }
        let now = clock.monotonicMilliseconds()
        let remainingMilliseconds = offerDeadlineMilliseconds > now
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
            await self.expireOffer()
        }
    }

    private func expireOffer() async {
        guard state == .offer
            || state == .awaitingRequesterHandshake
            || state == .awaitingResponderHandshake
            || state == .awaitingFinalRequesterHandshake
        else { return }
        await fail(.offerExpired)
    }

    private static func deadline(startedAt: UInt64, lifetime: UInt64) -> UInt64 {
        let (deadline, overflow) = startedAt.addingReportingOverflow(lifetime)
        return overflow ? UInt64.max : deadline
    }
}
#endif
