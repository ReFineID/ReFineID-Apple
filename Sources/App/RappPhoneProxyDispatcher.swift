// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CoreNFC) && os(iOS)
  import CardCore
  import Foundation

  /// Exhaustive semantic dispatcher for one authenticated phone-side RAPP
  /// connection. It sees no wire frames and owns no transport capability.
  internal actor RappPhoneProxyDispatcher {
    private let inbox: RappAuthorizationInbox
    private let requireExplicitReconnect: @MainActor @Sendable () -> Void
    private var pin2ByOperation: [Data: String] = [:]

    internal init(
      inbox: RappAuthorizationInbox,
      requireExplicitReconnect: @escaping @MainActor @Sendable () -> Void
    ) {
      self.inbox = inbox
      self.requireExplicitReconnect = requireExplicitReconnect
    }

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
          let request = RappAuthorizationRequest(
            id: operationID.base64EncodedString(),
            requester: operation.displayContext
              ?? String(localized: "Paired device"),
            action: action
          )
          let decision = await inbox.ask(request)
          switch decision {
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

    private func executeSafeRead(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      switch operation.kind {
      case .inspectCard:
        await inspect(operationID: operationID, coordinator: coordinator)
      case .readIdentity:
        await readIdentity(operationID: operationID, coordinator: coordinator)
      case .readAuthenticationCertificate, .readSignatureCertificate:
        guard let accessNumber = CardCredentialStore.displayedCardAccessNumber() else {
          await invalid(operationID, coordinator: coordinator)
          return
        }
        let outcome = await RappNfcCardExecutor.readCertificate(
          cardAccessNumber: accessNumber,
          signatureCertificate: operation.kind == .readSignatureCertificate
        )
        await finishRead(outcome, operationID: operationID, coordinator: coordinator)
      case .browserAuthenticate, .signDocument:
        await invalid(operationID, coordinator: coordinator)
      }
    }

    private func executeCardCommand(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard
        let accessNumber = CardCredentialStore.displayedCardAccessNumber(),
        let keyProfile = operation.keyProfile,
        let algorithm = operation.algorithm
      else {
        await invalid(operationID, coordinator: coordinator)
        return
      }
      let outcome: RappNfcCardExecutor.Outcome
      switch operation.kind {
      case .browserAuthenticate:
        outcome = await RappNfcCardExecutor.browserAuthentication(
          cardAccessNumber: accessNumber,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: operation.digest
        )
      case .signDocument:
        guard let pin2 = pin2ByOperation.removeValue(forKey: operationID) else {
          await invalid(operationID, coordinator: coordinator)
          return
        }
        outcome = await RappNfcCardExecutor.signDocument(
          cardAccessNumber: accessNumber,
          pin2: pin2,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: operation.digest
        )
      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate:
        await invalid(operationID, coordinator: coordinator)
        return
      }
      await finishSignature(
        outcome,
        operationID: operationID,
        coordinator: coordinator
      )
    }

    private func inspect(
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      guard let accessNumber = CardCredentialStore.displayedCardAccessNumber() else {
        await invalid(operationID, coordinator: coordinator)
        return
      }
      switch await CardMaintenance.connectionSnapshot(
        cardAccessNumber: accessNumber
      ) {
      case .connected(let snapshot):
        guard let activation = snapshot.activationNeeds else {
          await invalid(operationID, coordinator: coordinator)
          return
        }
        do {
          try await coordinator.completeInspection(
            operationID: operationID,
            pin1Factory: activation.pin1,
            pin2Factory: activation.pin2,
            pin1Attempts: attempts(snapshot.report?.pin1),
            pin2Attempts: attempts(snapshot.report?.pin2),
            pukAttempts: attempts(snapshot.report?.puk)
          )
        } catch {
          await coordinator.close()
        }
      case .wrongCardAccessNumber:
        CardCredentialStore.forgetAll()
        await requireExplicitReconnect()
        try? await coordinator.credentialRejected(operationID: operationID)
      case .failed:
        try? await coordinator.cardRemovedBeforeTransmit(operationID: operationID)
      }
    }

    private func readIdentity(
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      guard let accessNumber = CardCredentialStore.displayedCardAccessNumber() else {
        await invalid(operationID, coordinator: coordinator)
        return
      }
      let outcome = await RappNfcCardExecutor.readCertificate(
        cardAccessNumber: accessNumber,
        signatureCertificate: false
      )
      guard case .result(let der) = outcome,
        let facts = CertificateFacts(der: der),
        let name = DistinguishedName.personalName(inName: facts.subjectName)
          ?? DistinguishedName.commonName(inName: facts.subjectName)
      else {
        await finishRead(outcome, operationID: operationID, coordinator: coordinator)
        return
      }
      do {
        try await coordinator.completeIdentity(
          operationID: operationID,
          displayName: name,
          personID: DistinguishedName.identifier(inName: facts.subjectName) ?? ""
        )
      } catch {
        await coordinator.close()
      }
    }

    private func finishRead(
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

    private func finishSignature(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      if case .result(let signature) = outcome {
        try? await coordinator.completeSignature(
          operationID: operationID,
          signature: signature
        )
      } else {
        await finishFailure(outcome, operationID: operationID, coordinator: coordinator)
      }
    }

    private func finishFailure(
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

    private func invalid(
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

    private func attempts(_ outcome: RetryProbeOutcome?) -> UInt8? {
      switch outcome {
      case .remaining(let count): count.attemptsRemaining
      case .locked: 0
      case .invalidated, .noInformation, .other, .verified, nil: nil
      }
    }
  }
#endif
