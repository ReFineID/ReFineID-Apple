// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A deterministic identity card used by demonstrations and automated tests.
///
/// The virtual card models card state separately from device state. Card
/// mutations therefore change the same retry counters and factory flags that a
/// physical card changes, while setup changes only the simulated device. No
/// global switch lives in CardCore: a caller must explicitly construct and
/// retain an instance.
public actor VirtualIDCard {
  private enum RetryThresholds {
    static let zeroAttempts: UInt8 = 0
    static let lowAttemptsThreshold: UInt8 = 2
  }

  // MARK: Nested Types

  /// How the simulated device reaches the card.
  public enum Transport: String, CaseIterable, Identifiable, Sendable {
    case nearField
    case reader

    // MARK: Computed Properties

    /// The value itself as its stable identity.
    public var id: Self { self }
  }

  /// The card generation, which decides what the activation entry is.
  ///
  /// Legacy cards accept their PUK as the activation code; current cards
  /// ship a preset activation PIN.
  public enum Generation: String, CaseIterable, Identifiable, Sendable {
    case activationCodeIsPuk
    case presetActivationPIN

    // MARK: Computed Properties

    /// The value itself as its stable identity.
    public var id: Self { self }
  }

  /// The condition of one on-card certificate as reads report it.
  public enum CertificateState: String, CaseIterable, Identifiable, Sendable {
    case valid
    case expired
    case revoked
    case unreadable
    case missing

    // MARK: Computed Properties

    /// The value itself as its stable identity.
    public var id: Self { self }
  }

  /// One PIN or PUK as stored on the simulated card.
  public struct CredentialState: Equatable, Sendable {

    // MARK: Properties

    /// The digits the card currently accepts.
    public var value: String
    /// Attempts left before the credential blocks.
    public var attemptsRemaining: UInt8
    /// True while the credential still holds its factory value.
    public var isFactoryValue: Bool

    // MARK: Lifecycle

    /// Creates a credential with the given digits and retry allowance.
    public init(
      value: String,
      attemptsRemaining: UInt8,
      isFactoryValue: Bool = false
    ) {
      self.value = value
      self.attemptsRemaining = attemptsRemaining
      self.isFactoryValue = isFactoryValue
    }

  }

  /// The card-side state: what a physical card itself stores and reports.
  public struct CardState: Equatable, Sendable {

    // MARK: Properties

    /// The transport this card connects over.
    public var transport: Transport
    /// True when a contact reader is attached.
    public var readerConnected: Bool
    /// True while the card is present on its transport.
    public var cardPresent: Bool
    /// The activation scheme generation of this card.
    public var generation: Generation
    /// The six-digit CAN printed on the card.
    public var cardAccessNumber: String
    /// The entry the card accepts when activating factory credentials.
    public var activationEntry: String
    /// PIN 1, the authentication credential.
    public var pin1: CredentialState
    /// PIN 2, the qualified-signature credential.
    public var pin2: CredentialState
    /// The PUK that recovers blocked PINs.
    public var puk: CredentialState
    /// The holder's name as printed on the card.
    public var holderName: String
    /// The identifier that names the holder in electronic services.
    public var electronicClientIdentifier: String
    /// The card serial used to name the token.
    public var tokenSerial: String
    /// The condition of the authentication certificate.
    public var authenticationCertificate: CertificateState
    /// The condition of the qualified signature certificate.
    public var signatureCertificate: CertificateState

    // MARK: Lifecycle

    /// Creates a fully specified card state.
    public init(
      transport: Transport,
      readerConnected: Bool,
      cardPresent: Bool,
      generation: Generation,
      cardAccessNumber: String,
      activationEntry: String,
      pin1: CredentialState,
      pin2: CredentialState,
      puk: CredentialState,
      holderName: String,
      electronicClientIdentifier: String,
      tokenSerial: String,
      authenticationCertificate: CertificateState,
      signatureCertificate: CertificateState
    ) {
      self.transport = transport
      self.readerConnected = readerConnected
      self.cardPresent = cardPresent
      self.generation = generation
      self.cardAccessNumber = cardAccessNumber
      self.activationEntry = activationEntry
      self.pin1 = pin1
      self.pin2 = pin2
      self.puk = puk
      self.holderName = holderName
      self.electronicClientIdentifier = electronicClientIdentifier
      self.tokenSerial = tokenSerial
      self.authenticationCertificate = authenticationCertificate
      self.signatureCertificate = signatureCertificate
    }

  }

  /// What the simulated device remembers independently of the card.
  public struct DeviceState: Equatable, Sendable {

    // MARK: Properties

    /// The CAN saved on the device for future near-field connections.
    public var storedCardAccessNumber: String?
    /// The CAN in use on the currently open near-field connection.
    public var connectedCardAccessNumber: String?
    /// True once PIN 1 has been taken into use on this device.
    public var hasPin1: Bool
    /// True once the device has cached the holder's identity.
    public var cachedIdentity: Bool
    /// True once the device has published the card as a token.
    public var tokenRegistered: Bool
    /// True while a signature authorization is in flight.
    public var pendingSigningRequest: Bool

    // MARK: Lifecycle

    /// Creates device state; every field defaults to a fresh device.
    public init(
      storedCardAccessNumber: String? = nil,
      connectedCardAccessNumber: String? = nil,
      hasPin1: Bool = false,
      cachedIdentity: Bool = false,
      tokenRegistered: Bool = false,
      pendingSigningRequest: Bool = false
    ) {
      self.storedCardAccessNumber = storedCardAccessNumber
      self.connectedCardAccessNumber = connectedCardAccessNumber
      self.hasPin1 = hasPin1
      self.cachedIdentity = cachedIdentity
      self.tokenRegistered = tokenRegistered
      self.pendingSigningRequest = pendingSigningRequest
    }

  }

  /// One observable moment: card state, device state, and queued faults.
  public struct Snapshot: Equatable, Sendable {

    // MARK: Properties

    /// The card-side state.
    public var card: CardState
    /// The device-side state.
    public var device: DeviceState
    /// Transport faults waiting to fire, in queue order.
    public var faults: [Fault]

    // MARK: Lifecycle

    /// Creates a snapshot, with no faults queued by default.
    public init(
      card: CardState,
      device: DeviceState,
      faults: [Fault] = []
    ) {
      self.card = card
      self.device = device
      self.faults = faults
    }

  }

  /// A preset snapshot the virtual card can start from or reset to.
  public enum Scenario: String, CaseIterable, Identifiable, Sendable {
    case factoryFreshNearField = "factory-fresh-nfc"
    case legacyFactoryFreshNearField = "legacy-factory-fresh-nfc"
    case partialActivationNearField = "partial-activation-nfc"
    case activatedNearField = "activated-nfc"
    case registeredNearField = "registered-nfc"
    case factoryFreshReader = "factory-fresh-reader"
    case activatedReader = "activated-reader"
    case pin1RecoveryReader = "pin1-recovery-reader"
    case pin2RecoveryReader = "pin2-recovery-reader"
    case pukRecoveryRefusedReader = "puk-recovery-refused-reader"
    case absent

    // MARK: Computed Properties

    /// The value itself as its stable identity.
    public var id: Self { self }

    /// Whether the scenario connects over the near-field transport.
    public var usesNearField: Bool {
      switch self {
      case .factoryFreshNearField,
        .legacyFactoryFreshNearField,
        .partialActivationNearField,
        .activatedNearField,
        .registeredNearField:
        true
      case .factoryFreshReader,
        .activatedReader,
        .pin1RecoveryReader,
        .pin2RecoveryReader,
        .pukRecoveryRefusedReader,
        .absent:
        false
      }
    }

    /// The card and device state this scenario begins with.
    public var snapshot: Snapshot {
      let accessNumber = "123456"
      let activationPIN = "1234567"
      let defaultPIN1 = "1234"
      let defaultPIN2 = "123456"
      let defaultPUK = "12345678"
      var card = CardState(
        transport: .nearField,
        readerConnected: false,
        cardPresent: true,
        generation: .presetActivationPIN,
        cardAccessNumber: accessNumber,
        activationEntry: activationPIN,
        pin1: CredentialState(
          value: defaultPIN1,
          attemptsRemaining: RetryCount.pristineAllowance),
        pin2: CredentialState(
          value: defaultPIN2,
          attemptsRemaining: RetryCount.pristineAllowance),
        puk: CredentialState(
          value: defaultPUK,
          attemptsRemaining: RetryCount.pristineAllowance),
        holderName: "DOE JANE",
        electronicClientIdentifier: "12345678N",
        tokenSerial: "XA1234567",
        authenticationCertificate: .valid,
        signatureCertificate: .valid)
      var device = DeviceState()

      switch self {
      case .factoryFreshNearField:
        card.pin1 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)
        card.pin2 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)
      case .legacyFactoryFreshNearField:
        card.generation = .activationCodeIsPuk
        card.activationEntry = defaultPUK
        card.pin1 = CredentialState(
          value: defaultPIN1,
          attemptsRemaining: 0,
          isFactoryValue: true)
        card.pin2 = CredentialState(
          value: defaultPIN2,
          attemptsRemaining: 0,
          isFactoryValue: true)
      case .partialActivationNearField:
        card.pin2 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)
      case .activatedNearField:
        break
      case .registeredNearField:
        device = DeviceState(
          storedCardAccessNumber: accessNumber,
          connectedCardAccessNumber: accessNumber,
          hasPin1: true,
          cachedIdentity: true,
          tokenRegistered: true)
      case .factoryFreshReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin1 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)
        card.pin2 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)
      case .activatedReader:
        card.transport = .reader
        card.readerConnected = true
      case .pin1RecoveryReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin1.attemptsRemaining = RetryThresholds.lowAttemptsThreshold
      case .pin2RecoveryReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin2.attemptsRemaining = RetryThresholds.lowAttemptsThreshold
      case .pukRecoveryRefusedReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin1.attemptsRemaining = RetryThresholds.zeroAttempts
        card.puk.attemptsRemaining = RetryThresholds.lowAttemptsThreshold
      case .absent:
        card.cardPresent = false
      }
      return Snapshot(card: card, device: device)
    }
  }

  /// A card operation that a queued fault can intercept.
  public enum Operation: String, CaseIterable, Identifiable, Sendable {
    case any
    case connect
    case probeCredentials
    case changePIN1
    case changePIN2
    case resetPIN1
    case resetPIN2
    case activatePIN1
    case activatePIN2
    case authenticate
    case publishToken
    case authenticateSignature
    case qualifiedSignature

    // MARK: Computed Properties

    /// The value itself as its stable identity.
    public var id: Self { self }
  }

  /// The point within an operation at which a fault fires.
  ///
  /// A fault before the command prevents the card from acting; a fault
  /// after card execution loses only the response, leaving the card's
  /// state change in place.
  public enum FaultPhase: String, CaseIterable, Identifiable, Sendable {
    case beforeCommand
    case afterCardExecution

    // MARK: Computed Properties

    /// The value itself as its stable identity.
    public var id: Self { self }
  }

  /// The failure surfaced to the caller when a fault fires.
  public enum FaultEffect: String, CaseIterable, Identifiable, Sendable {
    case connectionLost
    case readerDisconnected
    case cardRemoved
    case timeout
    case malformedResponse
    case tokenNotPublished

    // MARK: Computed Properties

    /// The value itself as its stable identity.
    public var id: Self { self }
  }

  /// A deterministic transport failure queued against one operation.
  public struct Fault: Equatable, Sendable {

    // MARK: Properties

    /// The operation this fault intercepts.
    public var operation: Operation
    /// The phase at which the fault fires.
    public var phase: FaultPhase
    /// The failure surfaced when the fault fires.
    public var effect: FaultEffect
    /// How many more times the fault fires before it expires.
    public var remainingOccurrences: Int

    // MARK: Lifecycle

    /// Creates a fault that fires at least once.
    public init(
      operation: Operation,
      phase: FaultPhase,
      effect: FaultEffect,
      remainingOccurrences: Int = 1
    ) {
      self.operation = operation
      self.phase = phase
      self.effect = effect
      self.remainingOccurrences = max(1, remainingOccurrences)
    }

  }

  /// A named fault queue for common failure demonstrations.
  public enum FaultPreset: String, CaseIterable, Identifiable, Sendable {
    case none
    case nfcDisconnectBeforeConnection
    case readerFailsCounterQuery
    case cardRemovedDuringPINChange
    case responseLostAfterPIN1Activation
    case responseLostAfterPIN2Activation
    case certificateReadFailure
    case tokenPublicationFailure
    case cardRemovedDuringSignature
    case responseLostAfterSignature

    // MARK: Computed Properties

    /// The value itself as its stable identity.
    public var id: Self { self }

    /// Whether the fault can only occur on the near-field transport.
    public var usesNearField: Bool {
      self == .nfcDisconnectBeforeConnection
    }

    /// The fault queue this preset enqueues.
    public var faults: [Fault] {
      switch self {
      case .none:
        []
      case .nfcDisconnectBeforeConnection:
        [Fault(operation: .connect, phase: .beforeCommand, effect: .connectionLost)]
      case .readerFailsCounterQuery:
        [
          Fault(
            operation: .probeCredentials,
            phase: .beforeCommand,
            effect: .readerDisconnected)
        ]
      case .cardRemovedDuringPINChange:
        [
          Fault(
            operation: .changePIN1,
            phase: .beforeCommand,
            effect: .cardRemoved)
        ]
      case .responseLostAfterPIN1Activation:
        [
          Fault(
            operation: .activatePIN1,
            phase: .afterCardExecution,
            effect: .connectionLost)
        ]
      case .responseLostAfterPIN2Activation:
        [
          Fault(
            operation: .activatePIN2,
            phase: .afterCardExecution,
            effect: .connectionLost)
        ]
      case .certificateReadFailure:
        [
          Fault(
            operation: .authenticate,
            phase: .beforeCommand,
            effect: .malformedResponse)
        ]
      case .tokenPublicationFailure:
        [
          Fault(
            operation: .authenticate,
            phase: .afterCardExecution,
            effect: .tokenNotPublished)
        ]
      case .cardRemovedDuringSignature:
        [
          Fault(
            operation: .qualifiedSignature,
            phase: .beforeCommand,
            effect: .cardRemoved)
        ]
      case .responseLostAfterSignature:
        [
          Fault(
            operation: .qualifiedSignature,
            phase: .afterCardExecution,
            effect: .connectionLost)
        ]
      }
    }
  }

  /// The outcome of connecting to the card.
  public enum ConnectionResult: Equatable, Sendable {
    case connected(Snapshot)
    case incorrectCardAccessNumber
    case unavailable(FaultEffect)
  }

  /// Attempts remaining for each credential, read without side effects.
  public struct RetryReport: Equatable, Sendable {

    // MARK: Properties

    /// Attempts remaining for PIN 1.
    public let pin1: UInt8
    /// Attempts remaining for PIN 2.
    public let pin2: UInt8
    /// Attempts remaining for the PUK.
    public let puk: UInt8

    // MARK: Lifecycle

    /// Creates a report from the three counters.
    public init(pin1: UInt8, pin2: UInt8, puk: UInt8) {
      self.pin1 = pin1
      self.pin2 = pin2
      self.puk = puk
    }

  }

  /// The outcome of probing the retry counters.
  public enum ProbeResult: Equatable, Sendable {
    case report(RetryReport)
    case unreadable
    case unavailable(FaultEffect)
  }

  /// The outcome of one credential operation at the card boundary.
  ///
  /// The retry floor refuses verification outright at one or two remaining
  /// attempts rather than risk blocking the credential.
  public enum CredentialOutcome: Equatable, Sendable {
    case success
    case alreadyActivated
    case invalidEntry
    case blocked
    case rejected(remaining: UInt8)
    case refusedLowAttempts(remaining: UInt8)
    case transportFailure(FaultEffect)
  }

  /// A credential outcome paired with the snapshot it produced.
  public struct MutationResult: Equatable, Sendable {

    // MARK: Properties

    /// The outcome at the card boundary.
    public let outcome: CredentialOutcome
    /// The state after the operation.
    public let snapshot: Snapshot

    // MARK: Lifecycle

    /// Pairs an outcome with the resulting snapshot.
    public init(outcome: CredentialOutcome, snapshot: Snapshot) {
      self.outcome = outcome
      self.snapshot = snapshot
    }

  }

  /// The entry and new PINs offered to activate factory credentials.
  public struct ActivationRequest: Equatable, Sendable {

    // MARK: Properties

    /// The activation code offered to the card.
    public let entry: String
    /// The new PIN 1 to set, when PIN 1 needs activation.
    public let newPIN1: String?
    /// The new PIN 2 to set, when PIN 2 needs activation.
    public let newPIN2: String?

    // MARK: Lifecycle

    /// Creates a request from the entry and the optional new PINs.
    public init(entry: String, newPIN1: String?, newPIN2: String?) {
      self.entry = entry
      self.newPIN1 = newPIN1
      self.newPIN2 = newPIN2
    }

  }

  /// Per-PIN activation outcomes with the snapshot they produced.
  public struct ActivationResult: Equatable, Sendable {

    // MARK: Properties

    /// The outcome for PIN 1.
    public let pin1: CredentialOutcome
    /// The outcome for PIN 2, or nil when PIN 2 was never attempted.
    public let pin2: CredentialOutcome?
    /// The state after the activation attempt.
    public let snapshot: Snapshot

    // MARK: Lifecycle

    /// Pairs the per-PIN outcomes with the resulting snapshot.
    public init(
      pin1: CredentialOutcome,
      pin2: CredentialOutcome?,
      snapshot: Snapshot
    ) {
      self.pin1 = pin1
      self.pin2 = pin2
      self.snapshot = snapshot
    }

  }

  /// The outcome of authenticating with PIN 1.
  public enum AuthenticationResult: Equatable, Sendable {
    case success(Snapshot)
    case invalidEntry
    case blocked
    case rejected(remaining: UInt8)
    case refusedLowAttempts(remaining: UInt8)
    case certificateUnavailable
    case tokenPublicationFailed(Snapshot)
    case transportFailure(FaultEffect)
  }

  /// The card boundary exercised by a qualified document signature.
  public enum SignatureResult: Equatable, Sendable {
    case success
    case invalidEntry
    case blocked
    case rejected(remaining: UInt8)
    case refusedLowAttempts(remaining: UInt8)
    case certificateUnavailable
    case transportFailure(FaultEffect)
  }

  // MARK: Properties

  private var current: Snapshot

  // MARK: Computed Properties

  private var activationRequired: Bool {
    current.card.pin1.isFactoryValue || current.card.pin2.isFactoryValue
  }

  private var activationEntryDigitCount: Int {
    switch current.card.generation {
    case .activationCodeIsPuk:
      Puk.maximumDigitCount
    case .presetActivationPIN:
      Puk.minimumDigitCount
    }
  }

  // MARK: Lifecycle

  /// Creates a card preset to the given scenario.
  public init(scenario: Scenario = .factoryFreshNearField) {
    current = scenario.snapshot
  }

  /// Creates a card holding exactly the given snapshot.
  public init(snapshot: Snapshot) {
    current = snapshot
  }

  // MARK: Functions

  /// Reads the current snapshot without changing anything.
  public func inspect() -> Snapshot {
    current
  }

  /// Replaces the entire snapshot, queued faults included.
  public func replace(with snapshot: Snapshot) {
    current = snapshot
  }

  /// Discards all state and starts over from the scenario's snapshot.
  public func reset(to scenario: Scenario) {
    current = scenario.snapshot
  }

  /// Queues a fault to fire on its next matching operation.
  public func enqueue(_ fault: Fault) {
    current.faults.append(fault)
  }

  /// Discards every queued fault.
  public func clearFaults() {
    current.faults = []
  }

  /// Restores the simulated device to a fresh state, leaving the card as is.
  public func forgetDeviceState() {
    current.device = DeviceState()
  }

  /// Opens a connection, checking the CAN on the near-field transport.
  ///
  /// A successful near-field connection to an activated card also stores
  /// the CAN on the device.
  public func connect(cardAccessNumber: String) -> ConnectionResult {
    if let failure = reachabilityFailure() {
      current.device.connectedCardAccessNumber = nil
      return .unavailable(failure)
    }
    if let fault = consumeFault(for: .connect, phase: .beforeCommand) {
      current.device.connectedCardAccessNumber = nil
      return .unavailable(fault)
    }
    if current.card.transport == .nearField,
      !digitsAreValid(
        cardAccessNumber,
        within: CardAccessNumber.digitCount...CardAccessNumber.digitCount)
        || cardAccessNumber != current.card.cardAccessNumber
    {
      current.device.connectedCardAccessNumber = nil
      return .incorrectCardAccessNumber
    }
    current.device.connectedCardAccessNumber =
      current.card.transport == .nearField
      ? current.card.cardAccessNumber
      : nil
    if let fault = consumeFault(for: .connect, phase: .afterCardExecution) {
      current.device.connectedCardAccessNumber = nil
      return .unavailable(fault)
    }
    if current.card.transport == .nearField, !activationRequired {
      current.device.storedCardAccessNumber = current.card.cardAccessNumber
    }
    return .connected(current)
  }

  /// Reads the three retry counters without spending an attempt.
  public func probeCredentials() -> ProbeResult {
    if let failure = operationFailure() {
      return .unavailable(failure)
    }
    if let fault = consumeFault(for: .probeCredentials, phase: .beforeCommand) {
      return fault == .malformedResponse ? .unreadable : .unavailable(fault)
    }
    let report = RetryReport(
      pin1: current.card.pin1.attemptsRemaining,
      pin2: current.card.pin2.attemptsRemaining,
      puk: current.card.puk.attemptsRemaining)
    if let fault = consumeFault(
      for: .probeCredentials,
      phase: .afterCardExecution)
    {
      return fault == .malformedResponse ? .unreadable : .unavailable(fault)
    }
    return .report(report)
  }

  /// Changes PIN 1 after verifying the current PIN 1.
  public func changePIN1(current entered: String, new: String) -> MutationResult {
    change(
      role: .pin1,
      operation: .changePIN1,
      current: entered,
      new: new)
  }

  /// Changes PIN 2 after verifying the current PIN 2.
  public func changePIN2(current entered: String, new: String) -> MutationResult {
    change(
      role: .pin2,
      operation: .changePIN2,
      current: entered,
      new: new)
  }

  /// Sets a new PIN 1 after verifying the PUK.
  public func resetPIN1(puk: String, new: String) -> MutationResult {
    reset(role: .pin1, operation: .resetPIN1, puk: puk, new: new)
  }

  /// Sets a new PIN 2 after verifying the PUK.
  public func resetPIN2(puk: String, new: String) -> MutationResult {
    reset(role: .pin2, operation: .resetPIN2, puk: puk, new: new)
  }

  /// Activates factory PINs using the card's activation entry.
  ///
  /// PIN 1 is activated first and PIN 2 only after PIN 1 succeeds; on
  /// legacy cards the PUK's retry counter guards the entry.
  public func activate(_ request: ActivationRequest) -> ActivationResult {
    let needsPIN1 = current.card.pin1.isFactoryValue
    let needsPIN2 = current.card.pin2.isFactoryValue
    guard needsPIN1 || needsPIN2 else {
      return ActivationResult(
        pin1: .alreadyActivated,
        pin2: nil,
        snapshot: current)
    }
    guard
      digitsAreValid(
        request.entry,
        within: activationEntryDigitCount...activationEntryDigitCount)
    else {
      return ActivationResult(
        pin1: .invalidEntry,
        pin2: nil,
        snapshot: current)
    }
    if needsPIN1,
      request.newPIN1.map({ credentialIsValid($0, for: .pin1) }) != true
    {
      return ActivationResult(
        pin1: .invalidEntry,
        pin2: nil,
        snapshot: current)
    }
    if needsPIN2,
      request.newPIN2.map({ credentialIsValid($0, for: .pin2) }) != true
    {
      return ActivationResult(
        pin1: needsPIN1 ? .invalidEntry : .alreadyActivated,
        pin2: .invalidEntry,
        snapshot: current)
    }

    var pin1Outcome: CredentialOutcome = .alreadyActivated
    if needsPIN1, let newPIN1 = request.newPIN1 {
      pin1Outcome = activateCredential(
        role: .pin1,
        operation: .activatePIN1,
        entry: request.entry,
        new: newPIN1)
      guard pin1Outcome == .success else {
        return ActivationResult(
          pin1: pin1Outcome,
          pin2: nil,
          snapshot: current)
      }
    }

    var pin2Outcome: CredentialOutcome? = .alreadyActivated
    if needsPIN2, let newPIN2 = request.newPIN2 {
      pin2Outcome = activateCredential(
        role: .pin2,
        operation: .activatePIN2,
        entry: request.entry,
        new: newPIN2)
    }
    let pin1Completed =
      pin1Outcome == .success
      || pin1Outcome == .alreadyActivated
    let pin2Completed =
      pin2Outcome.map {
        $0 == .success || $0 == .alreadyActivated
      } ?? true
    if current.card.transport == .nearField,
      !activationRequired,
      pin1Completed,
      pin2Completed
    {
      current.device.storedCardAccessNumber =
        current.device.connectedCardAccessNumber
        ?? current.card.cardAccessNumber
    }
    return ActivationResult(
      pin1: pin1Outcome,
      pin2: pin2Outcome,
      snapshot: current)
  }

  /// Authenticates with PIN 1 and registers the card's token on the device.
  public func authenticate(pin1: String) -> AuthenticationResult {
    guard credentialIsValid(pin1, for: .pin1) else { return .invalidEntry }
    if let failure = operationFailure() {
      return .transportFailure(failure)
    }
    if let fault = consumeFault(for: .authenticate, phase: .beforeCommand) {
      return .transportFailure(fault)
    }
    guard current.card.authenticationCertificate == .valid else {
      return .certificateUnavailable
    }
    if let refusal = retryRefusal(current.card.pin1.attemptsRemaining) {
      return authenticationResult(from: refusal)
    }
    if pin1 != current.card.pin1.value {
      current.card.pin1.attemptsRemaining -= 1
      let remaining = current.card.pin1.attemptsRemaining
      return remaining == 0 ? .blocked : .rejected(remaining: remaining)
    }
    current.card.pin1.attemptsRemaining = RetryCount.pristineAllowance
    if let fault = consumeFault(for: .authenticate, phase: .afterCardExecution) {
      if fault == .tokenNotPublished {
        current.device.hasPin1 = true
        current.device.cachedIdentity = true
        current.device.tokenRegistered = false
        return .tokenPublicationFailed(current)
      }
      return .transportFailure(fault)
    }
    current.device.storedCardAccessNumber =
      current.device.connectedCardAccessNumber
      ?? current.device.storedCardAccessNumber
      ?? current.card.cardAccessNumber
    current.device.hasPin1 = true
    current.device.cachedIdentity = true
    current.device.tokenRegistered = true
    return .success(current)
  }

  /// Authorizes one virtual qualified signature with the same retry floor
  /// and state transitions as the physical card boundary.
  public func authorizeQualifiedSignature(pin2: String) -> SignatureResult {
    current.device.pendingSigningRequest = true
    guard credentialIsValid(pin2, for: .pin2) else {
      return finishSignature(.invalidEntry)
    }
    if let failure = operationFailure() {
      return finishSignature(.transportFailure(failure))
    }
    if let fault = consumeFault(
      for: .qualifiedSignature,
      phase: .beforeCommand)
    {
      return finishSignature(.transportFailure(fault))
    }
    guard current.card.signatureCertificate == .valid else {
      return finishSignature(.certificateUnavailable)
    }
    switch current.card.pin2.attemptsRemaining {
    case RetryThresholds.zeroAttempts:
      return finishSignature(.blocked)
    case 1...RetryThresholds.lowAttemptsThreshold:
      return finishSignature(
        .refusedLowAttempts(remaining: current.card.pin2.attemptsRemaining))
    default:
      break
    }
    if pin2 != current.card.pin2.value {
      current.card.pin2.attemptsRemaining -= 1
      let remaining = current.card.pin2.attemptsRemaining
      return finishSignature(
        remaining == 0 ? .blocked : .rejected(remaining: remaining))
    }
    current.card.pin2.attemptsRemaining = RetryCount.pristineAllowance
    if let fault = consumeFault(
      for: .qualifiedSignature,
      phase: .afterCardExecution)
    {
      return finishSignature(.transportFailure(fault))
    }
    return finishSignature(.success)
  }

  private func finishSignature(_ result: SignatureResult) -> SignatureResult {
    current.device.pendingSigningRequest = false
    return result
  }

  private func reachabilityFailure() -> FaultEffect? {
    guard current.card.cardPresent else { return .cardRemoved }
    if current.card.transport == .reader, !current.card.readerConnected {
      return .readerDisconnected
    }
    return nil
  }

  private func operationFailure() -> FaultEffect? {
    if let failure = reachabilityFailure() {
      return failure
    }
    if current.card.transport == .nearField {
      let offered =
        current.device.connectedCardAccessNumber
        ?? current.device.storedCardAccessNumber
      guard offered == current.card.cardAccessNumber else {
        return .connectionLost
      }
    }
    return nil
  }

  private func change(
    role: CredentialRole,
    operation: Operation,
    current entered: String,
    new: String
  ) -> MutationResult {
    guard credentialIsValid(entered, for: role),
      credentialIsValid(new, for: role),
      entered != new
    else {
      return MutationResult(outcome: .invalidEntry, snapshot: current)
    }
    if let failure = operationFailure() {
      return MutationResult(
        outcome: .transportFailure(failure),
        snapshot: current)
    }
    if let fault = consumeFault(for: operation, phase: .beforeCommand) {
      return MutationResult(
        outcome: .transportFailure(fault),
        snapshot: current)
    }
    var credential = credential(for: role)
    if let refusal = retryRefusal(credential.attemptsRemaining) {
      return MutationResult(outcome: refusal, snapshot: current)
    }
    let outcome: CredentialOutcome
    if entered != credential.value {
      credential.attemptsRemaining -= 1
      setCredential(credential, for: role)
      outcome =
        credential.attemptsRemaining == 0
        ? .blocked
        : .rejected(remaining: credential.attemptsRemaining)
    } else {
      credential.value = new
      credential.attemptsRemaining = RetryCount.pristineAllowance
      credential.isFactoryValue = false
      setCredential(credential, for: role)
      outcome = .success
    }
    if let fault = consumeFault(for: operation, phase: .afterCardExecution) {
      return MutationResult(
        outcome: .transportFailure(fault),
        snapshot: current)
    }
    return MutationResult(outcome: outcome, snapshot: current)
  }

  private func reset(
    role: CredentialRole,
    operation: Operation,
    puk enteredPUK: String,
    new: String
  ) -> MutationResult {
    guard
      digitsAreValid(
        enteredPUK,
        within: Puk.minimumDigitCount...Puk.maximumDigitCount),
      credentialIsValid(new, for: role)
    else {
      return MutationResult(outcome: .invalidEntry, snapshot: current)
    }
    if let failure = operationFailure() {
      return MutationResult(
        outcome: .transportFailure(failure),
        snapshot: current)
    }
    if let fault = consumeFault(for: operation, phase: .beforeCommand) {
      return MutationResult(
        outcome: .transportFailure(fault),
        snapshot: current)
    }
    if let refusal = retryRefusal(current.card.puk.attemptsRemaining) {
      return MutationResult(outcome: refusal, snapshot: current)
    }
    let outcome: CredentialOutcome
    if enteredPUK != current.card.puk.value {
      current.card.puk.attemptsRemaining -= 1
      outcome =
        current.card.puk.attemptsRemaining == 0
        ? .blocked
        : .rejected(remaining: current.card.puk.attemptsRemaining)
    } else {
      var target = credential(for: role)
      target.value = new
      target.attemptsRemaining = RetryCount.pristineAllowance
      target.isFactoryValue = false
      setCredential(target, for: role)
      current.card.puk.attemptsRemaining = RetryCount.pristineAllowance
      outcome = .success
    }
    if let fault = consumeFault(for: operation, phase: .afterCardExecution) {
      return MutationResult(
        outcome: .transportFailure(fault),
        snapshot: current)
    }
    return MutationResult(outcome: outcome, snapshot: current)
  }

  private func activateCredential(
    role: CredentialRole,
    operation: Operation,
    entry: String,
    new: String
  ) -> CredentialOutcome {
    if let failure = operationFailure() {
      return .transportFailure(failure)
    }
    if let fault = consumeFault(for: operation, phase: .beforeCommand) {
      return .transportFailure(fault)
    }
    let checkedRole: CredentialRole =
      current.card.generation == .activationCodeIsPuk ? .puk : role
    var checked = credential(for: checkedRole)
    if let refusal = retryRefusal(checked.attemptsRemaining) {
      return refusal
    }
    if entry != current.card.activationEntry {
      checked.attemptsRemaining -= 1
      setCredential(checked, for: checkedRole)
      return checked.attemptsRemaining == 0
        ? .blocked
        : .rejected(remaining: checked.attemptsRemaining)
    }
    var target = credential(for: role)
    target.value = new
    target.attemptsRemaining = RetryCount.pristineAllowance
    target.isFactoryValue = false
    setCredential(target, for: role)
    if checkedRole == .puk {
      current.card.puk.attemptsRemaining = RetryCount.pristineAllowance
    }
    if let fault = consumeFault(for: operation, phase: .afterCardExecution) {
      return .transportFailure(fault)
    }
    return .success
  }

  private func retryRefusal(_ remaining: UInt8) -> CredentialOutcome? {
    switch remaining {
    case RetryThresholds.zeroAttempts:
      .blocked
    case 1...RetryThresholds.lowAttemptsThreshold:
      .refusedLowAttempts(remaining: remaining)
    default:
      nil
    }
  }

  private func authenticationResult(
    from outcome: CredentialOutcome
  ) -> AuthenticationResult {
    switch outcome {
    case .blocked:
      .blocked
    case .refusedLowAttempts(let remaining):
      .refusedLowAttempts(remaining: remaining)
    case .transportFailure(let effect):
      .transportFailure(effect)
    case .rejected(let remaining):
      .rejected(remaining: remaining)
    case .success, .alreadyActivated, .invalidEntry:
      .invalidEntry
    }
  }

  private func credentialIsValid(
    _ digits: String,
    for role: CredentialRole
  ) -> Bool {
    switch role {
    case .pin1:
      digitsAreValid(
        digits,
        within: Pin1.minimumDigitCount...Pin1.maximumDigitCount)
    case .pin2:
      digitsAreValid(
        digits,
        within: Pin2.minimumDigitCount...Pin2.maximumDigitCount)
    case .puk:
      digitsAreValid(
        digits,
        within: Puk.minimumDigitCount...Puk.maximumDigitCount)
    }
  }

  private func digitsAreValid(
    _ digits: String,
    within allowedCount: ClosedRange<Int>
  ) -> Bool {
    let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
    return allowedCount.contains(digits.count)
      && digits.utf8.allSatisfy { asciiDigits.contains($0) }
  }

  private func credential(for role: CredentialRole) -> CredentialState {
    switch role {
    case .pin1:
      current.card.pin1
    case .pin2:
      current.card.pin2
    case .puk:
      current.card.puk
    }
  }

  private func setCredential(
    _ credential: CredentialState,
    for role: CredentialRole
  ) {
    switch role {
    case .pin1:
      current.card.pin1 = credential
    case .pin2:
      current.card.pin2 = credential
    case .puk:
      current.card.puk = credential
    }
  }

  private func consumeFault(
    for operation: Operation,
    phase: FaultPhase
  ) -> FaultEffect? {
    guard
      let index = current.faults.firstIndex(where: { fault in
        (fault.operation == operation || fault.operation == .any)
          && fault.phase == phase
      })
    else {
      return nil
    }
    let effect = current.faults[index].effect
    if current.faults[index].remainingOccurrences > 1 {
      current.faults[index].remainingOccurrences -= 1
    } else {
      current.faults.remove(at: index)
    }
    switch effect {
    case .readerDisconnected:
      current.card.readerConnected = false
      current.card.cardPresent = false
    case .cardRemoved:
      current.card.cardPresent = false
    case .connectionLost, .timeout, .malformedResponse, .tokenNotPublished:
      break
    }
    return effect
  }
}
