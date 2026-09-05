// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// Exhaustive semantic dispatcher for one authenticated phone-side RAPP
  /// connection. It sees no wire frames and owns no transport capability.
  internal actor RappPhoneProxyDispatcher {
    // MARK: Properties

    internal let inbox: RappAuthorizationInbox
    internal let requireExplicitReconnect: @MainActor @Sendable () -> Void
    internal var pin1ByOperation: [Data: String] = [:]
    internal var pin2ByOperation: [Data: String] = [:]
    internal var pin2Window = Pin2Window()

    // MARK: Lifecycle

    internal init(
      inbox: RappAuthorizationInbox,
      requireExplicitReconnect: @escaping @MainActor @Sendable () -> Void
    ) {
      self.inbox = inbox
      self.requireExplicitReconnect = requireExplicitReconnect
    }

    // MARK: Static Functions

    /// The remembered name of the selected pair's requesting device.
    private static func requesterName() async -> String? {
      let catalog = RappPairCatalog(vault: RappDeviceVault())
      guard let selected = try? await catalog.selectedPair() else {
        return nil
      }
      return RappPairNames.name(forPairID: selected.pairID)
    }

    /// Printed serial of the currently primed identity, if available.
    internal static func storedTokenSerial() -> String? {
      guard let tokenSerial = PrimeStore.storedIdentities().first?.tokenSerial else {
        return nil
      }
      if let serial = TokenSerial(value: tokenSerial),
        let printed = PrintedCardSerial(tokenSerial: serial)
      {
        return printed.value.lowercased()
      }
      return tokenSerial.lowercased()
    }

    // MARK: Functions

    internal func receive(
      _ event: RappConnectionCoordinator.Event,
      from coordinator: RappConnectionCoordinator
    ) async {
      switch event {
      case .established, .peerBusy:
        return

      case .inspectPrerequisites(let operationID, let operation):
        await inspectPrerequisites(
          operationID: operationID, operation: operation, coordinator: coordinator)

      case .awaitUserApproval(let operationID, let operation):
        await handleApproval(
          operationID: operationID, operation: operation, coordinator: coordinator)

      case .executeSafeRead(let operationID, let operation):
        await executeSafeRead(
          operationID: operationID, operation: operation, coordinator: coordinator)

      case .executeCardCommand(let operationID, let operation):
        await executeCardCommand(
          operationID: operationID, operation: operation, coordinator: coordinator)

      case .advisoryCancellation(let operationID),
        .operationFinished(let operationID),
        .peerUnknownOperation(let operationID),
        .terminal(let operationID, _, _):
        await cancel(operationID)

      case .completed:
        await coordinator.close()

      case .closed:
        await cleanup()
      }
    }

    private func cleanup() async {
      pin1ByOperation.removeAll(keepingCapacity: false)
      pin2ByOperation.removeAll(keepingCapacity: false)
      pin2Window.forget()
      await inbox.cancelAll()
    }

    private func inspectPrerequisites(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard prerequisitesExist(for: operation) else {
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
        return
      }
      try? await coordinator.prerequisitesComplete(operationID: operationID)
    }

    private func tryAutoApprove(
      operationID: Data,
      operation: RappOperationDriver.Operation
    ) async -> Bool {
      if operation.kind.isSafeRead {
        #if DEBUG
          HolderTrace.say("handleApproval: safe read auto-approved")
        #endif
        return true
      }
      if operation.kind == .signDocument, let pin2 = pin2Window.current() {
        #if DEBUG
          HolderTrace.say("handleApproval: using held pin2 window")
        #endif
        pin2ByOperation[operationID] = pin2
        return true
      }
      if operation.kind == .browserAuthenticate {
        let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
        if isReader, let pin1 = await cachedReaderPin1() {
          #if DEBUG
            HolderTrace.say("handleApproval: using cached reader PIN 1")
          #endif
          pin1ByOperation[operationID] = pin1
          return true
        }
        if !isReader, let storedPin1 = CardCredentialStore.pin1Digits() {
          #if DEBUG
            HolderTrace.say("handleApproval: using stored unattended PIN 1")
          #endif
          pin1ByOperation[operationID] = storedPin1
          return true
        }
      }
      return false
    }

    private func handleApproval(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      #if DEBUG
        HolderTrace.say(
          "handleApproval: kind=\(operation.kind), isSafeRead=\(operation.kind.isSafeRead)"
        )
      #endif
      guard let action = action(for: operation.kind) else {
        #if DEBUG
          HolderTrace.say(
            "handleApproval: rejected because no action mapping for \(operation.kind)"
          )
        #endif
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
        return
      }
      if await tryAutoApprove(operationID: operationID, operation: operation) {
        try? await coordinator.approve(operationID: operationID)
        return
      }
      let request = RappAuthorizationRequest(
        requestID: operationID.base64EncodedString(),
        requester: await Self.requesterName()
          ?? operation.displayContext
          ?? String(localized: "Paired device"),
        action: action
      )
      #if DEBUG
        HolderTrace.say("handleApproval: asking holder authorization for \(operation.kind)")
      #endif
      let decision = await inbox.ask(request)
      #if DEBUG
        HolderTrace.say("handleApproval: holder decided \(decision)")
      #endif
      await resolveApprovalDecision(
        decision,
        operationID: operationID,
        operation: operation,
        coordinator: coordinator
      )
    }

    private func resolveApprovalDecision(
      _ decision: RappAuthorizationDecision,
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      #if DEBUG
        HolderTrace.say("resolveApprovalDecision: \(decision) for \(operation.kind)")
      #endif
      switch decision {
      case .approved:
        try? await coordinator.approve(operationID: operationID)

      case .approvedBrowserAuthentication(let pin1):
        guard operation.kind == .browserAuthenticate else {
          try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
          return
        }
        pin1ByOperation[operationID] = pin1
        let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
        if isReader {
          await rememberReaderPin1(pin1)
        }
        try? await coordinator.approve(operationID: operationID)

      case .approvedDocumentSignature(let pin2):
        guard operation.kind == .signDocument else {
          try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
          return
        }
        pin2Window.hold(pin2)
        pin2ByOperation[operationID] = pin2
        try? await coordinator.approve(operationID: operationID)

      case .denied:
        try? await coordinator.deny(operationID: operationID)
      }
    }

    private func prerequisitesExist(
      for operation: RappOperationDriver.Operation
    ) -> Bool {
      switch operation.kind {
      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate:
        return operation.keyProfile == nil
          && operation.algorithm == nil
          && operation.digest.isEmpty

      case .browserAuthenticate:
        return hasSigningDescriptor(operation)

      case .signDocument:
        return hasSigningDescriptor(operation)
      }
    }

    private func hasSigningDescriptor(
      _ operation: RappOperationDriver.Operation
    ) -> Bool {
      operation.keyProfile != nil
        && operation.algorithm != nil
        && !operation.digest.isEmpty
    }

    private func action(
      for kind: RappOperationDriver.OperationKind
    ) -> RappAuthorizationRequest.Action? {
      switch kind {
      case .browserAuthenticate:
        .browserAuthentication

      case .signDocument:
        .documentSignature

      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate:
        .shareCardInformation
      }
    }

    private func cachedReaderPin1() async -> String? {
      await MainActor.run {
        guard CardPresence.shared.isReaderCardPresent else {
          ReaderPin1Cache.shared.clear()
          return nil
        }
        return ReaderPin1Cache.shared.current()
      }
    }

    private func rememberReaderPin1(_ pin1: String) async {
      await MainActor.run {
        guard CardPresence.shared.isReaderCardPresent else { return }
        ReaderPin1Cache.shared.remember(pin1)
      }
    }
  }
#endif
