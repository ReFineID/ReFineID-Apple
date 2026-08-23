// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS) && REFINEID_REMOTE_CARD
  import CardCore
  import Foundation

  /// Exhaustive semantic dispatcher for one authenticated phone-side RAPP
  /// connection. It sees no wire frames and owns no transport capability.
  internal actor RappPhoneProxyDispatcher {
    // MARK: Properties

    internal let inbox: RappAuthorizationInbox
    internal let requireExplicitReconnect: @MainActor @Sendable () -> Void
    internal var pin2ByOperation: [Data: String] = [:]

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
      pin2ByOperation.removeAll(keepingCapacity: false)
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

    private func handleApproval(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard let action = action(for: operation.kind) else {
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
        return
      }
      if operation.kind.isSafeRead || operation.kind == .browserAuthenticate {
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
      await resolveApprovalDecision(
        await inbox.ask(request),
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
      switch decision {
      case .approved:
        try? await coordinator.approve(operationID: operationID)

      case .approvedDocumentSignature(let pin2):
        guard operation.kind == .signDocument else {
          try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
          return
        }
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
        return CardCredentialStore.contents().hasPin1 && hasSigningDescriptor(operation)

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
  }
#endif
