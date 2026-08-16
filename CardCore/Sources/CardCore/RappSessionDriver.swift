#if canImport(ReFineIDRapp)
import Foundation
import ReFineIDRapp

/// Transport-independent coordinator for the authenticated RAPP session setup.
///
/// The surrounding transport may carry bytes and report closure, but it must not
/// interpret RAPP frames or decide protocol state. Card operations may start only
/// after this driver emits ``Command/established``.
public actor RappSessionDriver {
    public enum Role: Sendable {
        case requester
        case proxy
    }

    public enum CloseReason: Sendable, Equatable {
        case localRequest
        case transportClosed
        case protocolFailure
        case pairRevoked
    }

    public enum Command: Sendable, Equatable {
        /// Deliver these opaque bytes to the selected transport peer.
        case send(Data)
        /// Noise KK and mutual authenticated readiness have completed.
        case established
        /// Tear down the physical transport and discard the session driver.
        case closed(CloseReason)
    }

    private enum State: Equatable {
        case idle
        case awaitingRequesterHandshake
        case awaitingResponderHandshake
        case awaitingRequesterReady
        case awaitingResponderReady
        case established
        case operationsTransferred
        case closed
    }

    private let role: Role
    private let pairID: Data
    private let vault: RappDeviceVault
    private let session: RappSessionBridge
    private let entropy: RappPlatformEntropy
    private let clock: RappPlatformClock
    private var state = State.idle

    public init(
        role: Role,
        pair: RappPairRecord,
        vault: RappDeviceVault,
        entropy: RappPlatformEntropy = RappPlatformEntropy(),
        clock: RappPlatformClock = RappPlatformClock()
    ) throws {
        self.role = role
        self.pairID = try pair.metadata().pairId
        self.vault = vault
        self.entropy = entropy
        self.clock = clock

        switch role {
        case .requester:
            self.session = try RappSessionBridge.beginRequester(pair: pair, vault: vault)
        case .proxy:
            self.session = try RappSessionBridge.beginProxy(pair: pair, vault: vault)
        }
    }

    /// Starts a fresh session. The requester emits the first Noise KK frame;
    /// the proxy waits for it. Reusing a driver is a protocol error.
    public func start() -> [Command] {
        guard state == .idle else {
            return failClosed()
        }

        do {
            switch role {
            case .requester:
                let frame = try session.writeHandshakeFrame()
                state = .awaitingResponderHandshake
                return [.send(frame)]
            case .proxy:
                state = .awaitingRequesterHandshake
                return []
            }
        } catch {
            return failClosed()
        }
    }

    /// Consumes one complete opaque frame received from the selected peer.
    public func receive(_ frame: Data) -> [Command] {
        do {
            switch state {
            case .awaitingRequesterHandshake:
                try session.readHandshakeFrame(bytes: frame)
                let response = try session.writeHandshakeFrame()
                guard try session.handshakeComplete() else {
                    return failClosed()
                }
                try session.enterAuthentication()
                state = .awaitingRequesterReady
                return [.send(response)]

            case .awaitingResponderHandshake:
                try session.readHandshakeFrame(bytes: frame)
                guard try session.handshakeComplete() else {
                    return failClosed()
                }
                try session.enterAuthentication()
                let ready = try session.sendReady(nonce: entropy.sessionReadyNonce())
                state = .awaitingResponderReady
                return [.send(ready)]

            case .awaitingRequesterReady:
                try session.receiveReady(bytes: frame, nowMs: clock.wallMilliseconds())
                let ready = try session.sendReady(nonce: entropy.sessionReadyNonce())
                try session.enterEstablished()
                state = .established
                return [.send(ready), .established]

            case .awaitingResponderReady:
                try session.receiveReady(bytes: frame, nowMs: clock.wallMilliseconds())
                try session.enterEstablished()
                state = .established
                return [.established]

            case .idle, .established, .operationsTransferred, .closed:
                return failClosed()
            }
        } catch {
            return failClosed()
        }
    }

    public func transportClosed() -> [Command] {
        guard state != .closed else {
            return []
        }
        closeSession()
        return [.closed(.transportClosed)]
    }

    public func close() -> [Command] {
        guard state != .closed else {
            return []
        }
        closeSession()
        return [.closed(.localRequest)]
    }

    public func isEstablished() -> Bool {
        state == .established && (try? session.isEstablished()) == true
    }

    /// Transfers the established Noise session into the durable operation
    /// runtime. After this succeeds, all received frames belong to the returned
    /// driver and this handshake driver must be discarded.
    public func beginOperationDriver(
        maximumLifetimeMilliseconds: UInt64,
        liveness: RappOperationDriver.Liveness
    ) throws -> RappOperationDriver {
        guard state == .established, (try? session.isEstablished()) == true else {
            throw RappOperationDriver.LocalError.wrongPhase
        }
        let driver = try RappOperationDriver(
            role: role,
            session: session,
            vault: vault,
            maximumLifetimeMilliseconds: maximumLifetimeMilliseconds,
            liveness: liveness,
            entropy: entropy,
            clock: clock
        )
        state = .operationsTransferred
        return driver
    }

    private func failClosed() -> [Command] {
        let pairWasRevoked = (try? vault.isRevoked(pairId: pairID)) == true
        closeSession()
        return [.closed(pairWasRevoked ? .pairRevoked : .protocolFailure)]
    }

    private func closeSession() {
        if state != .closed {
            try? session.closeSession()
            state = .closed
        }
    }
}
#endif
