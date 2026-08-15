// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A deterministic identity card used by demonstrations and automated tests.
///
/// The virtual card models card state separately from device state. Card
/// mutations therefore change the same retry counters and factory flags that a
/// physical card changes, while setup changes only the simulated device. No
/// global switch lives in CardCore: a caller must explicitly construct and
/// retain an instance.
public actor VirtualIDCard {
  public enum Transport: String, CaseIterable, Identifiable, Sendable {
    case nearField
    case reader

    public var id: Self { self }
  }

  public enum Generation: String, CaseIterable, Identifiable, Sendable {
    case activationCodeIsPuk
    case presetActivationPIN

    public var id: Self { self }
  }

  public enum CertificateState: String, CaseIterable, Identifiable, Sendable {
    case valid
    case expired
    case revoked
    case unreadable
    case missing

    public var id: Self { self }
  }

  public struct CredentialState: Equatable, Sendable {
    public var value: String
    public var attemptsRemaining: UInt8
    public var isFactoryValue: Bool

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

  public struct CardState: Equatable, Sendable {
    public var transport: Transport
    public var readerConnected: Bool
    public var cardPresent: Bool
    public var generation: Generation
    public var cardAccessNumber: String
    public var activationEntry: String
    public var pin1: CredentialState
    public var pin2: CredentialState
    public var puk: CredentialState
    public var holderName: String
    public var electronicClientIdentifier: String
    public var tokenSerial: String
    public var authenticationCertificate: CertificateState
    public var signatureCertificate: CertificateState

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

  public struct DeviceState: Equatable, Sendable {
    public var storedCardAccessNumber: String?
    public var connectedCardAccessNumber: String?
    public var hasPin1: Bool
    public var cachedIdentity: Bool
    public var tokenRegistered: Bool
    public var pendingSigningRequest: Bool

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

  public struct Snapshot: Equatable, Sendable {
    public var card: CardState
    public var device: DeviceState
    public var faults: [Fault]

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

    public var id: Self { self }

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
        tokenSerial: "VIRTUAL-ID-CARD-0001",
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
        card.pin1.attemptsRemaining = 2
      case .pin2RecoveryReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin2.attemptsRemaining = 2
      case .pukRecoveryRefusedReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin1.attemptsRemaining = 0
        card.puk.attemptsRemaining = 2
      case .absent:
        card.cardPresent = false
      }
      return Snapshot(card: card, device: device)
    }
  }

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

    public var id: Self { self }
  }

  public enum FaultPhase: String, CaseIterable, Identifiable, Sendable {
    case beforeCommand
    case afterCardExecution

    public var id: Self { self }
  }

  public enum FaultEffect: String, CaseIterable, Identifiable, Sendable {
    case connectionLost
    case readerDisconnected
    case cardRemoved
    case timeout
    case malformedResponse
    case tokenNotPublished

    public var id: Self { self }
  }

  public struct Fault: Equatable, Sendable {
    public var operation: Operation
    public var phase: FaultPhase
    public var effect: FaultEffect
    public var remainingOccurrences: Int

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

    public var id: Self { self }

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

  public enum ConnectionResult: Equatable, Sendable {
    case connected(Snapshot)
    case incorrectCardAccessNumber
    case unavailable(FaultEffect)
  }

  public struct RetryReport: Equatable, Sendable {
    public let pin1: UInt8
    public let pin2: UInt8
    public let puk: UInt8

    public init(pin1: UInt8, pin2: UInt8, puk: UInt8) {
      self.pin1 = pin1
      self.pin2 = pin2
      self.puk = puk
    }
  }

  public enum ProbeResult: Equatable, Sendable {
    case report(RetryReport)
    case unreadable
    case unavailable(FaultEffect)
  }

  public enum CredentialOutcome: Equatable, Sendable {
    case success
    case alreadyActivated
    case invalidEntry
    case blocked
    case rejected(remaining: UInt8)
    case refusedLowAttempts(remaining: UInt8)
    case transportFailure(FaultEffect)
  }

  public struct MutationResult: Equatable, Sendable {
    public let outcome: CredentialOutcome
    public let snapshot: Snapshot

    public init(outcome: CredentialOutcome, snapshot: Snapshot) {
      self.outcome = outcome
      self.snapshot = snapshot
    }
  }

  public struct ActivationRequest: Equatable, Sendable {
    public let entry: String
    public let newPIN1: String?
    public let newPIN2: String?

    public init(entry: String, newPIN1: String?, newPIN2: String?) {
      self.entry = entry
      self.newPIN1 = newPIN1
      self.newPIN2 = newPIN2
    }
  }

  public struct ActivationResult: Equatable, Sendable {
    public let pin1: CredentialOutcome
    public let pin2: CredentialOutcome?
    public let snapshot: Snapshot

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

  private var current: Snapshot

  public init(scenario: Scenario = .factoryFreshNearField) {
    current = scenario.snapshot
  }

  public init(snapshot: Snapshot) {
    current = snapshot
  }

  public func inspect() -> Snapshot {
    current
  }

  public func replace(with snapshot: Snapshot) {
    current = snapshot
  }

  public func reset(to scenario: Scenario) {
    current = scenario.snapshot
  }

  public func enqueue(_ fault: Fault) {
    current.faults.append(fault)
  }

  public func clearFaults() {
    current.faults = []
  }

  public func forgetDeviceState() {
    current.device = DeviceState()
  }

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
      (!digitsAreValid(
        cardAccessNumber,
        within: CardAccessNumber.digitCount...CardAccessNumber.digitCount)
        || cardAccessNumber != current.card.cardAccessNumber)
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

  public func changePIN1(current entered: String, new: String) -> MutationResult {
    change(
      role: .pin1,
      operation: .changePIN1,
      current: entered,
      new: new)
  }

  public func changePIN2(current entered: String, new: String) -> MutationResult {
    change(
      role: .pin2,
      operation: .changePIN2,
      current: entered,
      new: new)
  }

  public func resetPIN1(puk: String, new: String) -> MutationResult {
    reset(role: .pin1, operation: .resetPIN1, puk: puk, new: new)
  }

  public func resetPIN2(puk: String, new: String) -> MutationResult {
    reset(role: .pin2, operation: .resetPIN2, puk: puk, new: new)
  }

  public func activate(_ request: ActivationRequest) -> ActivationResult {
    let needsPIN1 = current.card.pin1.isFactoryValue
    let needsPIN2 = current.card.pin2.isFactoryValue
    guard needsPIN1 || needsPIN2 else {
      return ActivationResult(
        pin1: .alreadyActivated,
        pin2: nil,
        snapshot: current)
    }
    guard digitsAreValid(
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
    let pin1Completed = pin1Outcome == .success
      || pin1Outcome == .alreadyActivated
    let pin2Completed = pin2Outcome.map {
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
    case 0:
      return finishSignature(.blocked)
    case 1, 2:
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
    guard digitsAreValid(
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
    case 0:
      .blocked
    case 1, 2:
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
