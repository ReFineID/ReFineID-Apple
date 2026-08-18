#if canImport(RappEngine)
  import Foundation
  import RappEngine
  /// Owns one established RAPP operation runtime and translates generated binding
  /// records into Sendable Apple-side values. It never performs card I/O itself.
  public actor RappOperationDriver {

    // MARK: Nested Types

    /// Local misuse of the driver or a bridge action missing a required field.
    public enum LocalError: Error, Sendable {
      case wrongPhase
      case missingOperation
      case missingOperationIdentifier
      case missingFrame
    }

    /// Caller-injected liveness polling policy with no hidden timing constants.
    public struct Liveness: Sendable, Equatable {

      // MARK: Properties

      /// Interval between liveness polls before any backoff.
      public let baseIntervalMilliseconds: UInt64
      /// Time allowed for the peer to answer one liveness challenge.
      public let responseTimeoutMilliseconds: UInt64
      /// Upper bound the polling interval may back off to.
      public let maximumIntervalMilliseconds: UInt64
      /// Largest random offset applied to a scheduled poll.
      public let maximumJitterMilliseconds: UInt64
      /// Consecutive unanswered challenges tolerated before closing.
      public let maximumMisses: UInt8

      // MARK: Computed Properties

      fileprivate var binding: RappLivenessConfiguration {
        RappLivenessConfiguration(
          baseIntervalMs: baseIntervalMilliseconds,
          responseTimeoutMs: responseTimeoutMilliseconds,
          maximumIntervalMs: maximumIntervalMilliseconds,
          maximumJitterMs: maximumJitterMilliseconds,
          maximumMisses: maximumMisses
        )
      }

      // MARK: Lifecycle

      /// Creates a policy from explicit caller-chosen bounds.
      public init(
        baseIntervalMilliseconds: UInt64,
        responseTimeoutMilliseconds: UInt64,
        maximumIntervalMilliseconds: UInt64,
        maximumJitterMilliseconds: UInt64,
        maximumMisses: UInt8
      ) {
        self.baseIntervalMilliseconds = baseIntervalMilliseconds
        self.responseTimeoutMilliseconds = responseTimeoutMilliseconds
        self.maximumIntervalMilliseconds = maximumIntervalMilliseconds
        self.maximumJitterMilliseconds = maximumJitterMilliseconds
        self.maximumMisses = maximumMisses
      }

    }

    /// Card signing key profile named by an operation request.
    public enum KeyProfile: Sendable, Equatable {
      case ecdsaP256
      case ecdsaP384
      case rsa2048
      case rsa3072

      // MARK: Computed Properties

      fileprivate var binding: RappCardKeyProfile {
        switch self {
        case .ecdsaP256:
          .ecdsaP256
        case .ecdsaP384:
          .ecdsaP384
        case .rsa2048:
          .rsa2048
        case .rsa3072:
          .rsa3072
        }
      }

      // MARK: Lifecycle

      fileprivate init(_ value: RappCardKeyProfile) {
        switch value {
        case .ecdsaP256:
          self = .ecdsaP256
        case .ecdsaP384:
          self = .ecdsaP384
        case .rsa2048:
          self = .rsa2048
        case .rsa3072:
          self = .rsa3072
        }
      }

    }

    /// Signature algorithm named by an operation request.
    public enum SignatureAlgorithm: Sendable, Equatable {
      case ecdsaSHA224
      case ecdsaSHA256
      case ecdsaSHA384
      case ecdsaSHA512
      case rsaPkcs1SHA256
      case rsaPkcs1SHA384
      case rsaPkcs1SHA512
      case rsaPssSHA256

      // MARK: Computed Properties

      fileprivate var binding: RappSignatureAlgorithm {
        switch self {
        case .ecdsaSHA224:
          .ecdsaSha224
        case .ecdsaSHA256:
          .ecdsaSha256
        case .ecdsaSHA384:
          .ecdsaSha384
        case .ecdsaSHA512:
          .ecdsaSha512
        case .rsaPkcs1SHA256:
          .rsaPkcs1Sha256
        case .rsaPkcs1SHA384:
          .rsaPkcs1Sha384
        case .rsaPkcs1SHA512:
          .rsaPkcs1Sha512
        case .rsaPssSHA256:
          .rsaPssSha256
        }
      }

      // MARK: Lifecycle

      fileprivate init(_ value: RappSignatureAlgorithm) {
        switch value {
        case .ecdsaSha224:
          self = .ecdsaSHA224
        case .ecdsaSha256:
          self = .ecdsaSHA256
        case .ecdsaSha384:
          self = .ecdsaSHA384
        case .ecdsaSha512:
          self = .ecdsaSHA512
        case .rsaPkcs1Sha256:
          self = .rsaPkcs1SHA256
        case .rsaPkcs1Sha384:
          self = .rsaPkcs1SHA384
        case .rsaPkcs1Sha512:
          self = .rsaPkcs1SHA512
        case .rsaPssSha256:
          self = .rsaPssSHA256
        }
      }

    }

    /// Kind of operation the requester asks the proxy to perform.
    public enum OperationKind: Sendable, Equatable {
      case inspectCard
      case readIdentity
      case readAuthenticationCertificate
      case readSignatureCertificate
      case browserAuthenticate
      case signDocument

      // MARK: Lifecycle

      fileprivate init(_ value: RappOperationKind) {
        switch value {
        case .inspectCard:
          self = .inspectCard
        case .readIdentity:
          self = .readIdentity
        case .readAuthenticationCertificate:
          self = .readAuthenticationCertificate
        case .readSignatureCertificate:
          self = .readSignatureCertificate
        case .browserAuthenticate:
          self = .browserAuthenticate
        case .signDocument:
          self = .signDocument
        }
      }
    }

    /// One requested operation, described without any local credentials.
    public struct Operation: Sendable, Equatable {

      // MARK: Properties

      /// Requested operation kind.
      public let kind: OperationKind
      /// User-visible request context such as an origin or a document name.
      public let displayContext: String?
      /// Card key profile for signing operations; nil otherwise.
      public let keyProfile: KeyProfile?
      /// Signature algorithm for signing operations; nil otherwise.
      public let algorithm: SignatureAlgorithm?
      /// Digest to be signed; empty for non-signing operations.
      public let digest: Data

      // MARK: Lifecycle

      fileprivate init(_ value: RappOperationDescriptor) {
        kind = OperationKind(value.kind)
        displayContext = value.displayContext
        keyProfile = value.keyProfile.map(KeyProfile.init)
        algorithm = value.algorithm.map(SignatureAlgorithm.init)
        digest = value.digest
      }

    }

    /// Kind of a successfully completed operation result.
    public enum ResultKind: Sendable, Equatable {
      case inspection
      case identity
      case certificate
      case signature

      // MARK: Lifecycle

      fileprivate init(_ value: RappResultKind) {
        switch value {
        case .inspection:
          self = .inspection
        case .identity:
          self = .identity
        case .certificate:
          self = .certificate
        case .signature:
          self = .signature
        }
      }
    }

    /// Successful operation result with only the fields its kind populates.
    public struct Result: Sendable, Equatable {

      // MARK: Properties

      /// Result kind that selects which optional fields are populated.
      public let kind: ResultKind
      /// Whether PIN 1 still carries its factory value; inspection only.
      public let pin1Factory: Bool?
      /// Whether PIN 2 still carries its factory value; inspection only.
      public let pin2Factory: Bool?
      /// Remaining PIN 1 attempts when the card reported them.
      public let pin1Attempts: UInt8?
      /// Remaining PIN 2 attempts when the card reported them.
      public let pin2Attempts: UInt8?
      /// Remaining PUK attempts when the card reported them.
      public let pukAttempts: UInt8?
      /// Cardholder display name carried by identity results.
      public let displayName: String?
      /// Cardholder person identifier carried by identity results.
      public let personID: String?
      /// Certificate DER or signature bytes; empty for other result kinds.
      public let bytes: Data

      // MARK: Lifecycle

      fileprivate init(_ value: RappOperationResult) {
        kind = ResultKind(value.kind)
        pin1Factory = value.pin1Factory
        pin2Factory = value.pin2Factory
        pin1Attempts = value.pin1Attempts
        pin2Attempts = value.pin2Attempts
        pukAttempts = value.pukAttempts
        displayName = value.displayName
        personID = value.personId
        bytes = value.bytes
      }

    }

    /// Reason an operation ended without delivering a result.
    public enum TerminalReason: Sendable, Equatable {
      case userDenied
      case requestExpired
      case cancelled
      case requestInvalidOrUnsupported
      case retryPolicyRefused
      case credentialRejected
      case cardRemovedBeforeTransmit
      case cardCompletionAmbiguous

      // MARK: Lifecycle

      fileprivate init(_ value: RappTerminalReason) {
        switch value {
        case .userDenied:
          self = .userDenied
        case .requestExpired:
          self = .requestExpired
        case .cancelled:
          self = .cancelled
        case .requestInvalidOrUnsupported:
          self = .requestInvalidOrUnsupported
        case .retryPolicyRefused:
          self = .retryPolicyRefused
        case .credentialRejected:
          self = .credentialRejected
        case .cardRemovedBeforeTransmit:
          self = .cardRemovedBeforeTransmit
        case .cardCompletionAmbiguous:
          self = .cardCompletionAmbiguous
        }
      }
    }

    /// Reason the operation session closed permanently.
    public enum CloseReason: Sendable, Equatable {
      case localRequest
      case transportClosed
      case protocolFailure
      case pairRevoked
      case terminalFrameReleased
    }

    /// A token that the transport must return after it has released a frame.
    public enum FrameRelease: Sendable, Equatable {
      case none
      case resultAcknowledgment(operationID:
        Data)
      case closeSession
    }

    /// Effect the caller must apply on behalf of the driver, which performs
    /// no card or transport I/O itself.
    public enum Command: Sendable, Equatable {
      case send(frame: Data, release:
        FrameRelease)
      case inspectPrerequisites(operationID: Data, operation:
        Operation)
      case awaitUserApproval(operationID: Data, operation:
        Operation)
      case executeSafeRead(operationID: Data, operation:
        Operation)
      case executeCardCommand(operationID: Data, operation:
        Operation)
      case completed(operationID: Data, result:
        Result)
      case terminal(operationID: Data?, state: String?, reason:
        TerminalReason?)
      case advisoryCancellation(operationID:
        Data?)
      case operationFinished(operationID:
        Data?)
      case peerBusy(operationID:
        Data?)
      case peerUnknownOperation(operationID:
        Data?)
      case scheduleLiveness(atMonotonicMilliseconds:
        UInt64)
      case closed(CloseReason)
    }

    private enum OperationCommandKind {
      case inspect
      case approval
      case safeRead
      case cardCommand
    }

    // MARK: Properties

    private let bridge: RappOperationBridge
    private let entropy: RappPlatformEntropy
    private let clock: RappPlatformClock
    private var closed = false

    // MARK: Lifecycle

    internal init(
      role: RappSessionDriver.Role,
      session: RappSessionBridge,
      vault: RappDeviceVault,
      maximumLifetimeMilliseconds: UInt64,
      liveness: Liveness,
      entropy: RappPlatformEntropy,
      clock: RappPlatformClock
    ) throws {
      self.entropy = entropy
      self.clock = clock
      let now = clock.monotonicMilliseconds()
      switch role {
      case .requester:
        bridge = try RappOperationBridge.beginRequester(
          session: session,
          vault: vault,
          maximumLifetimeMs: maximumLifetimeMilliseconds,
          liveness: liveness.binding,
          nowMs: now
        )
      case .proxy:
        bridge = try RappOperationBridge.beginProxy(
          session: session,
          vault: vault,
          maximumLifetimeMs: maximumLifetimeMilliseconds,
          liveness: liveness.binding,
          nowMs: now
        )
      }
    }

    // MARK: Functions

    /// Starts a requester inspection of card and PIN status.
    public func beginInspectCard(expiresAfterMilliseconds: UInt64) throws -> [Command] {
      try commands(
        bridge.beginInspectCard(
          operationId: entropy.operationID(),
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester read of the cardholder identity.
    public func beginReadIdentity(expiresAfterMilliseconds: UInt64) throws -> [Command] {
      try commands(
        bridge.beginReadIdentity(
          operationId: entropy.operationID(),
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester read of the authentication or signature certificate.
    public func beginReadCertificate(
      signatureCertificate: Bool,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginReadCertificate(
          operationId: entropy.operationID(),
          signatureCertificate: signatureCertificate,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester browser-authentication signature for the given origin.
    public func beginBrowserAuthentication(
      origin: String,
      keyProfile: KeyProfile,
      algorithm: SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginBrowserAuthentication(
          operationId: entropy.operationID(),
          origin: origin,
          keyProfile: keyProfile.binding,
          algorithm: algorithm.binding,
          digest: digest,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester document-signing operation for the named document.
    public func beginSignDocument(
      documentName: String,
      keyProfile: KeyProfile,
      algorithm: SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginSignDocument(
          operationId: entropy.operationID(),
          documentName: documentName,
          keyProfile: keyProfile.binding,
          algorithm: algorithm.binding,
          digest: digest,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Consumes one complete opaque frame received from the transport.
    public func receive(_ frame: Data) -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(
          bridge.receiveFrame(
            bytes: frame,
            nowMs: clock.monotonicMilliseconds()
          ))
      } catch {
        return protocolFailure()
      }
    }

    /// Marks bounded card-status and certificate prerequisites complete.
    public func prerequisitesComplete(operationID: Data) throws -> [Command] {
      try commands(bridge.prerequisitesComplete(operationId: operationID))
    }

    /// Approves exactly the request displayed by the authorizer UI.
    public func approve(operationID: Data) throws -> [Command] {
      try commands(
        bridge.approve(
          operationId: operationID,
          approvedAtMs: clock.monotonicMilliseconds()
        ))
    }

    /// Denies the exact request and emits a stable denial.
    public func deny(operationID: Data) throws -> [Command] {
      try commands(bridge.deny(operationId: operationID))
    }

    /// Rejects a request that is unsupported or contradicts the live card.
    public func requestInvalidOrUnsupported(operationID: Data) throws -> [Command] {
      try commands(bridge.requestInvalidOrUnsupported(operationId: operationID))
    }

    /// Reports that local retry policy refused the request.
    public func retryRefused(operationID: Data) throws -> [Command] {
      try commands(bridge.retryRefused(operationId: operationID))
    }

    /// Reports that the card rejected the presented credential.
    public func credentialRejected(operationID: Data) throws -> [Command] {
      try commands(
        bridge.credentialRejected(
          operationId: operationID,
          rejectedAtMs: clock.monotonicMilliseconds()
        ))
    }

    /// Reports that the card left the reader before the command was sent.
    public func cardRemovedBeforeTransmit(operationID: Data) throws -> [Command] {
      try commands(bridge.cardRemovedBeforeTransmit(operationId: operationID))
    }

    /// Reports that card completion could not be determined either way.
    public func cardCompletionAmbiguous(operationID: Data) throws -> [Command] {
      try commands(bridge.cardCompletionAmbiguous(operationId: operationID))
    }

    /// Completes an inspection with factory state and remaining attempt counts.
    public func completeInspection(
      operationID: Data,
      pin1Factory: Bool,
      pin2Factory: Bool,
      pin1Attempts: UInt8?,
      pin2Attempts: UInt8?,
      pukAttempts: UInt8?
    ) throws -> [Command] {
      try commands(
        bridge.completeInspection(
          operationId: operationID,
          pin1Factory: pin1Factory,
          pin2Factory: pin2Factory,
          pin1Attempts: pin1Attempts,
          pin2Attempts: pin2Attempts,
          pukAttempts: pukAttempts
        ))
    }

    /// Completes an identity read with the cardholder name and identifier.
    public func completeIdentity(
      operationID: Data,
      displayName: String,
      personID: String
    ) throws -> [Command] {
      try commands(
        bridge.completeIdentity(
          operationId: operationID,
          displayName: displayName,
          personId: personID
        ))
    }

    /// Completes a certificate read with DER bytes read from the card.
    public func completeCertificate(operationID: Data, der: Data) throws -> [Command] {
      try commands(bridge.completeCertificate(operationId: operationID, der: der))
    }

    /// Completes a signing operation with the card-produced signature.
    public func completeSignature(operationID: Data, signature: Data) throws -> [Command] {
      try commands(bridge.completeSignature(operationId: operationID, signature: signature))
    }

    /// Must be called only after the transport reports whether it released the
    /// corresponding frame.
    ///
    /// A failed release classifies all in-flight work as a closed or ambiguous
    /// session through the Rust engine.
    public func frameReleased(_ release: FrameRelease, succeeded: Bool) -> [Command] {
      guard !closed else { return [] }
      guard succeeded else { return transportClosed() }

      do {
        switch release {
        case .none:
          return []
        case .resultAcknowledgment(let operationID):
          let result = try bridge.acknowledgmentReleased(operationId: operationID)
          return [.completed(operationID: operationID, result: Result(result))]
        case .closeSession:
          closed = true
          return [.closed(.terminalFrameReleased)]
        }
      } catch {
        return protocolFailure()
      }
    }

    /// Advances authenticated liveness with fresh challenge bytes and the
    /// caller-generated jitter.
    public func pollLiveness(jitterMilliseconds: Int64) -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(
          bridge.pollLiveness(
            nowMs: clock.monotonicMilliseconds(),
            challenge: entropy.livenessChallenge(),
            jitterMs: jitterMilliseconds
          ))
      } catch {
        return protocolFailure()
      }
    }

    /// Closes the session after the transport reported closure.
    public func transportClosed() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = try? bridge.closeSession()
      return [.closed(.transportClosed)]
    }

    /// Closes the session at local request.
    public func close() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = try? bridge.closeSession()
      return [.closed(.localRequest)]
    }

    private func commands(_ action: RappBridgeAction) throws -> [Command] {
      if let frame = action.frame {
        let release: FrameRelease
        if action.kind == .resultAcknowledgment {
          guard let operationID = action.operationId else {
            throw LocalError.missingOperationIdentifier
          }
          release = .resultAcknowledgment(operationID: operationID)
        } else if action.closeSessionAfterSend {
          release = .closeSession
        } else {
          release = .none
        }
        return scheduled([.send(frame: frame, release: release)], for: action)
      }

      let operationID = action.operationId
      switch action.kind {
      case .inspectPrerequisites:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .inspect)],
          for: action
        )
      case .awaitUserApproval:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .approval)],
          for: action
        )
      case .executeSafeRead:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .safeRead)],
          for: action
        )
      case .executeCardCommand:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .cardCommand)],
          for: action
        )
      case .terminal, .cancelled:
        return scheduled(
          [
            .terminal(
              operationID: operationID,
              state: action.terminalState,
              reason: action.terminalReason.map(TerminalReason.init)
            )
          ], for: action)
      case .advisoryCancellation:
        return scheduled([.advisoryCancellation(operationID: operationID)], for: action)
      case .resultAcknowledged:
        return scheduled([.operationFinished(operationID: operationID)], for: action)
      case .peerBusy:
        return scheduled([.peerBusy(operationID: operationID)], for: action)
      case .peerUnknownOperation:
        return scheduled([.peerUnknownOperation(operationID: operationID)], for: action)
      case .sessionClosed:
        closed = true
        return [.closed(.protocolFailure)]
      case .pairRevoked:
        closed = true
        return [.closed(.pairRevoked)]
      case .sendFrame, .resultAcknowledgment:
        throw LocalError.missingFrame
      case .completed:
        throw LocalError.wrongPhase
      case .ignoredDuplicate, .noAction:
        return scheduled([], for: action)
      }
    }

    private func scheduled(
      _ commands: [Command],
      for action: RappBridgeAction
    ) -> [Command] {
      guard let deadline = action.nextPollAtMs else { return commands }
      return commands + [.scheduleLiveness(atMonotonicMilliseconds: deadline)]
    }

    private func operationCommand(
      _ action: RappBridgeAction,
      operationID: Data?,
      kind: OperationCommandKind
    ) throws -> Command {
      guard let operationID else { throw LocalError.missingOperationIdentifier }
      guard let descriptor = action.operation else { throw LocalError.missingOperation }
      let operation = Operation(descriptor)
      switch kind {
      case .inspect:
        return .inspectPrerequisites(operationID: operationID, operation: operation)
      case .approval:
        return .awaitUserApproval(operationID: operationID, operation: operation)
      case .safeRead:
        return .executeSafeRead(operationID: operationID, operation: operation)
      case .cardCommand:
        return .executeCardCommand(operationID: operationID, operation: operation)
      }
    }

    private func protocolFailure() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = try? bridge.closeSession()
      return [.closed(.protocolFailure)]
    }
  }
#endif
