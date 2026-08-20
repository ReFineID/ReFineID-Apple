// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// What the dispatcher asks of the card, and what it answers without one.
  extension RappPhoneProxyDispatcher {

    internal func executeSafeRead(
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
        // The authentication certificate is public and this device read it
        // once already, while setting its own identity up. A peer asking
        // for it is asking for something held here, so the card stays in
        // the holder's pocket.
        if operation.kind == .readAuthenticationCertificate,
          let primed = PrimeStore.primedAuthenticationCertificates().first
        {
          await finishRead(
            .result(primed),
            operationID: operationID,
            coordinator: coordinator)
          return
        }
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

    internal func executeCardCommand(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard
        let accessNumber = CardCredentialStore.displayedCardAccessNumber(),
        let keyProfile = operation.keyProfile,
        let algorithm = operation.algorithm
      else {
        #if DEBUG
          print(
            "[stream-holder] card command refused: access number "
              + "\(CardCredentialStore.displayedCardAccessNumber() != nil), "
              + "profile \(operation.keyProfile != nil), "
              + "algorithm \(operation.algorithm != nil)")
          fflush(stdout)
        #endif
        await invalid(operationID, coordinator: coordinator)
        return
      }
      #if DEBUG
        print("[stream-holder] card read starting: \(operation.kind)")
        fflush(stdout)
      #endif
      guard
        let outcome = await signingOutcome(
          operationID: operationID,
          operation: operation,
          accessNumber: accessNumber,
          keyProfile: keyProfile,
          algorithm: algorithm
        )
      else {
        await invalid(operationID, coordinator: coordinator)
        return
      }
      #if DEBUG
        print("[stream-holder] card read outcome: \(String(describing: outcome))")
        fflush(stdout)
      #endif
      await finishSignature(
        outcome,
        operationID: operationID,
        coordinator: coordinator
      )
    }

    /// What the card answered, or nothing when this operation is not one the
    /// card signs for.
    ///
    /// A document signature consumes the PIN2 held for the operation, so it
    /// is taken here and not before: an operation that never reaches the card
    /// leaves the PIN2 where it was.
    private func signingOutcome(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      accessNumber: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm
    ) async -> RappNfcCardExecutor.Outcome? {
      switch operation.kind {
      case .browserAuthenticate:
        await RappNfcCardExecutor.browserAuthentication(
          cardAccessNumber: accessNumber,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: operation.digest
        )
      case .signDocument:
        if let pin2 = pin2ByOperation.removeValue(forKey: operationID) {
          await RappNfcCardExecutor.signDocument(
            cardAccessNumber: accessNumber,
            pin2: pin2,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: operation.digest
          )
        } else {
          nil
        }
      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate:
        nil
      }
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
  }
#endif
