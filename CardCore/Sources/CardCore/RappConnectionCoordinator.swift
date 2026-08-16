#if canImport(ReFineIDRapp)
import Foundation
import ReFineIDRapp

/// The sole byte-transport capability required by RAPP. Implementations must
/// preserve frame boundaries and report successful release by returning from
/// ``send(_:)``. They must not parse, log, retry, or reinterpret frames.
public protocol RappFrameTransport: Sendable {
    func send(_ frame: Data) async throws
    func close() async
}

/// Runs one authenticated connection from Noise setup through durable card
/// operations. All externally visible events are semantic and authenticated.
public actor RappConnectionCoordinator {
    public enum CloseReason: Sendable, Equatable {
        case handshake(RappSessionDriver.CloseReason)
        case operation(RappOperationDriver.CloseReason)
        case transportFailure
        case localRequest
    }

    public enum Event: Sendable, Equatable {
        case established
        case inspectPrerequisites(
            operationID: Data,
            operation: RappOperationDriver.Operation
        )
        case awaitUserApproval(
            operationID: Data,
            operation: RappOperationDriver.Operation
        )
        case executeSafeRead(
            operationID: Data,
            operation: RappOperationDriver.Operation
        )
        case executeCardCommand(
            operationID: Data,
            operation: RappOperationDriver.Operation
        )
        case completed(
            operationID: Data,
            result: RappOperationDriver.Result
        )
        case terminal(
            operationID: Data?,
            state: String?,
            reason: RappOperationDriver.TerminalReason?
        )
        case advisoryCancellation(operationID: Data?)
        case operationFinished(operationID: Data?)
        case peerBusy(operationID: Data?)
        case peerUnknownOperation(operationID: Data?)
        case closed(CloseReason)
    }

    private enum Phase: Equatable {
        case handshaking
        case operating
        case closed
    }

    public nonisolated let events: AsyncStream<Event>

    private let transport: any RappFrameTransport
    private let handshake: RappSessionDriver
    private let maximumLifetimeMilliseconds: UInt64
    private let liveness: RappOperationDriver.Liveness
    private let clock: RappPlatformClock
    private let continuation: AsyncStream<Event>.Continuation
    private var operation: RappOperationDriver?
    private var phase = Phase.handshaking
    private var livenessTask: Task<Void, Never>?

    public init(
        role: RappSessionDriver.Role,
        pair: RappPairRecord,
        vault: RappDeviceVault,
        transport: any RappFrameTransport,
        maximumLifetimeMilliseconds: UInt64,
        liveness: RappOperationDriver.Liveness,
        clock: RappPlatformClock = RappPlatformClock()
    ) throws {
        self.transport = transport
        self.maximumLifetimeMilliseconds = maximumLifetimeMilliseconds
        self.liveness = liveness
        self.clock = clock
        self.handshake = try RappSessionDriver(
            role: role,
            pair: pair,
            vault: vault,
            clock: clock
        )

        var capturedContinuation: AsyncStream<Event>.Continuation?
        self.events = AsyncStream { capturedContinuation = $0 }
        guard let capturedContinuation else {
            preconditionFailure("AsyncStream did not provide a continuation")
        }
        self.continuation = capturedContinuation
    }

    deinit {
        livenessTask?.cancel()
        continuation.finish()
    }

    public func start() async {
        guard phase == .handshaking else { return }
        await handleHandshake(await handshake.start())
    }

    /// Delivers one complete frame received by the transport.
    public func receive(_ frame: Data) async {
        switch phase {
        case .handshaking:
            await handleHandshake(await handshake.receive(frame))
        case .operating:
            guard let operation else {
                await finish(.transportFailure)
                return
            }
            await handleOperation(await operation.receive(frame))
        case .closed:
            return
        }
    }

    public func beginInspectCard(expiresAfterMilliseconds: UInt64) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.beginInspectCard(
            expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    public func beginReadIdentity(expiresAfterMilliseconds: UInt64) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.beginReadIdentity(
            expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    public func beginReadCertificate(
        signatureCertificate: Bool,
        expiresAfterMilliseconds: UInt64
    ) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.beginReadCertificate(
            signatureCertificate: signatureCertificate,
            expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    public func beginBrowserAuthentication(
        origin: String,
        keyProfile: RappOperationDriver.KeyProfile,
        algorithm: RappOperationDriver.SignatureAlgorithm,
        digest: Data,
        expiresAfterMilliseconds: UInt64
    ) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.beginBrowserAuthentication(
            origin: origin,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: digest,
            expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    public func beginSignDocument(
        documentName: String,
        keyProfile: RappOperationDriver.KeyProfile,
        algorithm: RappOperationDriver.SignatureAlgorithm,
        digest: Data,
        expiresAfterMilliseconds: UInt64
    ) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.beginSignDocument(
            documentName: documentName,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: digest,
            expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    public func prerequisitesComplete(operationID: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.prerequisitesComplete(operationID: operationID))
    }

    public func approve(operationID: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.approve(operationID: operationID))
    }

    public func deny(operationID: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.deny(operationID: operationID))
    }

    public func requestInvalidOrUnsupported(operationID: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.requestInvalidOrUnsupported(
            operationID: operationID
        ))
    }

    public func retryRefused(operationID: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.retryRefused(operationID: operationID))
    }

    public func credentialRejected(operationID: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.credentialRejected(operationID: operationID))
    }

    public func cardRemovedBeforeTransmit(operationID: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.cardRemovedBeforeTransmit(
            operationID: operationID
        ))
    }

    public func cardCompletionAmbiguous(operationID: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.cardCompletionAmbiguous(
            operationID: operationID
        ))
    }

    public func completeInspection(
        operationID: Data,
        pin1Factory: Bool,
        pin2Factory: Bool,
        pin1Attempts: UInt8?,
        pin2Attempts: UInt8?,
        pukAttempts: UInt8?
    ) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.completeInspection(
            operationID: operationID,
            pin1Factory: pin1Factory,
            pin2Factory: pin2Factory,
            pin1Attempts: pin1Attempts,
            pin2Attempts: pin2Attempts,
            pukAttempts: pukAttempts
        ))
    }

    public func completeIdentity(
        operationID: Data,
        displayName: String,
        personID: String
    ) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.completeIdentity(
            operationID: operationID,
            displayName: displayName,
            personID: personID
        ))
    }

    public func completeCertificate(operationID: Data, der: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.completeCertificate(
            operationID: operationID,
            der: der
        ))
    }

    public func completeSignature(operationID: Data, signature: Data) async throws {
        let driver = try operationDriver()
        await handleOperation(try await driver.completeSignature(
            operationID: operationID,
            signature: signature
        ))
    }

    public func pollLiveness(jitterMilliseconds: Int64) async {
        guard phase == .operating, let operation else { return }
        await handleOperation(await operation.pollLiveness(
            jitterMilliseconds: jitterMilliseconds
        ))
    }

    public func transportClosed() async {
        switch phase {
        case .handshaking:
            await handleHandshake(await handshake.transportClosed())
        case .operating:
            guard let operation else {
                await finish(.transportFailure)
                return
            }
            await handleOperation(await operation.transportClosed())
        case .closed:
            return
        }
    }

    public func close() async {
        switch phase {
        case .handshaking:
            _ = await handshake.close()
        case .operating:
            if let operation { _ = await operation.close() }
        case .closed:
            return
        }
        await finish(.localRequest)
    }

    private func operationDriver() throws -> RappOperationDriver {
        guard phase == .operating, let operation else {
            throw RappOperationDriver.LocalError.wrongPhase
        }
        return operation
    }

    private func handleHandshake(_ commands: [RappSessionDriver.Command]) async {
        for command in commands where phase == .handshaking {
            switch command {
            case let .send(frame):
                do {
                    try await transport.send(frame)
                } catch {
                    _ = await handshake.transportClosed()
                    await finish(.transportFailure)
                }

            case .established:
                do {
                    operation = try await handshake.beginOperationDriver(
                        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds,
                        liveness: liveness
                    )
                    phase = .operating
                    continuation.yield(.established)
                    let now = clock.monotonicMilliseconds()
                    let (deadline, overflow) = now.addingReportingOverflow(
                        liveness.baseIntervalMilliseconds
                    )
                    scheduleLiveness(at: overflow ? UInt64.max : deadline)
                } catch {
                    await finish(.handshake(.protocolFailure))
                }

            case let .closed(reason):
                await finish(.handshake(reason))
            }
        }
    }

    private func handleOperation(_ commands: [RappOperationDriver.Command]) async {
        for command in commands where phase == .operating {
            switch command {
            case let .send(frame, release):
                do {
                    try await transport.send(frame)
                    guard let operation else {
                        await finish(.transportFailure)
                        return
                    }
                    await handleOperation(await operation.frameReleased(release, succeeded: true))
                } catch {
                    if let operation { _ = await operation.transportClosed() }
                    await finish(.transportFailure)
                }

            case let .inspectPrerequisites(operationID, operation):
                continuation.yield(.inspectPrerequisites(
                    operationID: operationID,
                    operation: operation
                ))
            case let .awaitUserApproval(operationID, operation):
                continuation.yield(.awaitUserApproval(
                    operationID: operationID,
                    operation: operation
                ))
            case let .executeSafeRead(operationID, operation):
                continuation.yield(.executeSafeRead(
                    operationID: operationID,
                    operation: operation
                ))
            case let .executeCardCommand(operationID, operation):
                continuation.yield(.executeCardCommand(
                    operationID: operationID,
                    operation: operation
                ))
            case let .completed(operationID, result):
                continuation.yield(.completed(operationID: operationID, result: result))
            case let .terminal(operationID, state, reason):
                continuation.yield(.terminal(
                    operationID: operationID,
                    state: state,
                    reason: reason
                ))
            case let .advisoryCancellation(operationID):
                continuation.yield(.advisoryCancellation(operationID: operationID))
            case let .operationFinished(operationID):
                continuation.yield(.operationFinished(operationID: operationID))
            case let .peerBusy(operationID):
                continuation.yield(.peerBusy(operationID: operationID))
            case let .peerUnknownOperation(operationID):
                continuation.yield(.peerUnknownOperation(operationID: operationID))
            case let .scheduleLiveness(deadline):
                scheduleLiveness(at: deadline)
            case let .closed(reason):
                await finish(.operation(reason))
            }
        }
    }

    private func scheduleLiveness(at deadline: UInt64) {
        guard phase == .operating else { return }
        livenessTask?.cancel()

        let now = clock.monotonicMilliseconds()
        let delayMilliseconds = deadline > now ? deadline - now : 0
        let (convertedDelay, overflow) = delayMilliseconds.multipliedReportingOverflow(
            by: 1_000_000
        )
        let delayNanoseconds = overflow ? UInt64.max : convertedDelay
        let maximumJitter = min(
            liveness.maximumJitterMilliseconds,
            UInt64(Int64.max)
        )

        livenessTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }

            var generator = SystemRandomNumberGenerator()
            let bound = Int64(maximumJitter)
            let jitter = Int64.random(in: -bound ... bound, using: &generator)
            await self.pollLiveness(jitterMilliseconds: jitter)
        }
    }

    private func finish(_ reason: CloseReason) async {
        guard phase != .closed else { return }
        phase = .closed
        livenessTask?.cancel()
        livenessTask = nil
        await transport.close()
        continuation.yield(.closed(reason))
        continuation.finish()
    }
}
#endif
