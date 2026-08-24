// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS) && REFINEID_REMOTE_CARD
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
        await fulfillCertificateRead(
          operationID: operationID,
          isSignature: operation.kind == .readSignatureCertificate,
          coordinator: coordinator)

      case .browserAuthenticate, .signDocument:
        await invalid(operationID, coordinator: coordinator)
      }
    }

    private func fulfillCertificateRead(
      operationID: Data,
      isSignature: Bool,
      coordinator: RappConnectionCoordinator
    ) async {
      if let primed = PrimeStore.storedIdentities().first {
        let cachedDER = isSignature ? primed.signatureCertDER : primed.certDER
        if let cachedDER {
          do {
            try await coordinator.completeCertificate(
              operationID: operationID,
              der: cachedDER,
              cardSerial: Self.storedTokenSerial()
            )
          } catch {
            await coordinator.close()
          }
          return
        }
      }
      let accessNumber = CardCredentialStore.displayedCardAccessNumber()
      let outcome = await RappCardExecutor.readCertificate(
        cardAccessNumber: accessNumber,
        signatureCertificate: isSignature
      )
      if case .result(let der) = outcome, isSignature {
        PrimeStore.updateSignatureCertificate(der)
      }
      await finishRead(outcome, operationID: operationID, coordinator: coordinator)
    }

    internal func executeCardCommand(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard
        let keyProfile = operation.keyProfile,
        let algorithm = operation.algorithm
      else {
        #if DEBUG
          print(
            "[stream-holder] card command refused: profile \(operation.keyProfile != nil), "
              + "algorithm \(operation.algorithm != nil)")
          fflush(stdout)
        #endif
        await invalid(operationID, coordinator: coordinator)
        return
      }
      let accessNumber = CardCredentialStore.displayedCardAccessNumber()
      #if DEBUG
        HolderTrace.say("card read starting: \(operation.kind)")
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
        HolderTrace.say("card read outcome: \(String(describing: outcome))")
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
      accessNumber: String?,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm
    ) async -> RappCardExecutor.Outcome? {
      switch operation.kind {
      case .browserAuthenticate:
        let pin1 = pin1ByOperation.removeValue(forKey: operationID)
        return await RappCardExecutor.browserAuthentication(
          cardAccessNumber: accessNumber,
          pin1: pin1,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: operation.digest
        )

      case .signDocument:
        guard let pin2 = pin2ByOperation.removeValue(forKey: operationID) else {
          return nil
        }
        return await RappCardExecutor.signDocument(
          cardAccessNumber: accessNumber,
          pin2: pin2,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: operation.digest
        )

      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate:
        return nil
      }
    }

    private func inspect(
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      let accessNumber = CardCredentialStore.displayedCardAccessNumber()
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
            inspection: RappOperationDriver.Inspection(
              pin1Factory: activation.pin1,
              pin2Factory: activation.pin2,
              pin1Attempts: attempts(snapshot.report?.pin1),
              pin2Attempts: attempts(snapshot.report?.pin2),
              pukAttempts: attempts(snapshot.report?.puk)
            )
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
      let accessNumber = CardCredentialStore.displayedCardAccessNumber()
      let outcome = await RappCardExecutor.readCertificate(
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
