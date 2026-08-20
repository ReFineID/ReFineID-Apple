// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// Exhaustive semantic dispatcher for one authenticated phone-side RAPP
  /// connection. It sees no wire frames and owns no transport capability.
  internal actor RappPhoneProxyDispatcher {

    // MARK: Properties

    private let inbox: RappAuthorizationInbox
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
      do {
        switch event {
        case .established:
          return

        case .inspectPrerequisites(let operationID, let operation):
          guard prerequisitesExist(for: operation) else {
            try await coordinator.requestInvalidOrUnsupported(
              operationID: operationID)
            return
          }
          try await coordinator.prerequisitesComplete(operationID: operationID)

        case .awaitUserApproval(let operationID, let operation):
          guard let action = action(for: operation.kind) else {
            try await coordinator.requestInvalidOrUnsupported(
              operationID: operationID)
            return
          }
          // The QR scan that paired this device, carrying the offer's 256-bit
          // bearer secret, is the human consent that authorizes this session.
          // Safe reads and browser authentication proceed without another
          // prompt: browser authentication signs with the already-stored PIN1
          // (its prerequisite check confirmed it), so nothing more is asked.
          // Only qualified document signing, which needs PIN2 entered per
          // signature, still prompts.
          if operation.kind.isSafeRead || operation.kind == .browserAuthenticate {
            try await coordinator.approve(operationID: operationID)
            return
          }
          let request = RappAuthorizationRequest(
            id: operationID.base64EncodedString(),
            requester: await Self.requesterName()
              ?? operation.displayContext
              ?? String(localized: "Paired device"),
            action: action
          )
          switch await inbox.ask(request) {
          case .approved:
            try await coordinator.approve(operationID: operationID)
          case .approvedDocumentSignature(let pin2):
            guard operation.kind == .signDocument else {
              try await coordinator.requestInvalidOrUnsupported(
                operationID: operationID)
              return
            }
            pin2ByOperation[operationID] = pin2
            try await coordinator.approve(operationID: operationID)
          case .denied:
            try await coordinator.deny(operationID: operationID)
          }

        case .executeSafeRead(let operationID, let operation):
          await executeSafeRead(
            operationID: operationID,
            operation: operation,
            coordinator: coordinator
          )

        case .executeCardCommand(let operationID, let operation):
          await executeCardCommand(
            operationID: operationID,
            operation: operation,
            coordinator: coordinator
          )

        case .advisoryCancellation(let operationID),
          .operationFinished(let operationID),
          .peerUnknownOperation(let operationID):
          await cancel(operationID)

        case .terminal(let operationID, _, _):
          await cancel(operationID)

        case .peerBusy:
          return

        case .completed:
          await coordinator.close()

        case .closed:
          pin2ByOperation.removeAll(keepingCapacity: false)
          await inbox.cancelAll()
        }
      } catch {
        pin2ByOperation.removeAll(keepingCapacity: false)
        await inbox.cancelAll()
        await coordinator.close()
      }
    }

    private func prerequisitesExist(
      for operation: RappOperationDriver.Operation
    ) -> Bool {
      let stored = CardCredentialStore.contents()
      guard stored.hasCardAccessNumber else { return false }
      switch operation.kind {
      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate:
        return operation.keyProfile == nil
          && operation.algorithm == nil
          && operation.digest.isEmpty
      case .browserAuthenticate:
        return stored.hasPin1 && hasSigningDescriptor(operation)
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

    internal func finishRead(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      if case .result(let bytes) = outcome {
        try? await coordinator.completeCertificate(
          operationID: operationID,
          der: bytes
        )
      } else {
        await finishFailure(outcome, operationID: operationID, coordinator: coordinator)
      }
    }

    internal func finishSignature(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      if case .result(let signature) = outcome {
        do {
          try await coordinator.completeSignature(
            operationID: operationID,
            signature: signature
          )
        } catch {
          #if DEBUG
            print("[stream-holder] answer refused: \(String(describing: error))")
            fflush(stdout)
          #endif
        }
      } else {
        await finishFailure(outcome, operationID: operationID, coordinator: coordinator)
      }
    }

    internal func finishFailure(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      switch outcome {
      case .result:
        await coordinator.close()
      case .rejected(let rejection):
        switch rejection {
        case .cardAccessNumber:
          CardCredentialStore.forgetAll()
        case .credential(.pin1, _):
          CardCredentialStore.forgetPin1()
        case .credential(.pin2, _), .credential(.puk, _):
          break
        }
        await requireExplicitReconnect()
        try? await coordinator.credentialRejected(operationID: operationID)
      case .refusedBeforeCredentialTransmit(let refusal):
        switch refusal {
        case .cardUnavailable:
          try? await coordinator.cardRemovedBeforeTransmit(operationID: operationID)
        case .credentialBlocked, .credentialInvalidated, .retryFloor:
          try? await coordinator.retryRefused(operationID: operationID)
        case .certificateUnavailable, .invalidCredential,
          .keyOrAlgorithmMismatch:
          try? await coordinator.requestInvalidOrUnsupported(
            operationID: operationID)
        }
      case .completionAmbiguous:
        await requireExplicitReconnect()
        try? await coordinator.cardCompletionAmbiguous(operationID: operationID)
      }
    }

    internal func invalid(
      _ operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
    }

    private func cancel(_ operationID: Data?) async {
      guard let operationID else {
        pin2ByOperation.removeAll(keepingCapacity: false)
        await inbox.cancelAll()
        return
      }
      pin2ByOperation.removeValue(forKey: operationID)
      await inbox.cancel(operationID.base64EncodedString())
    }

    internal func attempts(_ outcome: RetryProbeOutcome?) -> UInt8? {
      switch outcome {
      case .remaining(let count):
        count.attemptsRemaining
      case .locked:
        0
      case .invalidated, .noInformation, .other, .verified, nil:
        nil
      }
    }
  }
#endif
