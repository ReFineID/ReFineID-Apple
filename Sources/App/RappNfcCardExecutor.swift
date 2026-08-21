// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS) && REFINEID_REMOTE_CARD
  import CardCore
  import Foundation
  import Security

  /// The sole physical-card boundary for the iPhone RAPP proxy.
  ///
  /// Each call owns one NFC hold. Safe reads never accept credentials.
  /// Consequential calls validate the live certificate and retry state before
  /// constructing a one-shot PIN transmission. Once that transmission begins,
  /// every unclassified transport/card failure is completion-ambiguous rather
  /// than permission to retry.
  internal enum RappNfcCardExecutor {
    internal enum Refusal: Sendable, Equatable {
      case cardUnavailable
      case certificateUnavailable
      case credentialBlocked(CredentialRole)
      case credentialInvalidated(CredentialRole)
      case invalidCredential(CredentialRole)
      case keyOrAlgorithmMismatch
      case retryFloor(CredentialRole, RetryFloorVerdict)
    }

    internal enum Rejection: Sendable, Equatable {
      case cardAccessNumber
      case credential(CredentialRole, remaining: RetryCount?)
    }

    internal enum Outcome: Sendable, Equatable {
      case completionAmbiguous
      case refusedBeforeCredentialTransmit(Refusal)
      case rejected(Rejection)
      case result(Data)
    }

    private struct Identity {
      let publicKey: SecKey
      let request: SignRequest
    }

    private static var holdMessage: String {
      String(localized: "Hold your identity card near the top of the iPhone.")
    }

    internal static func readCertificate(
      cardAccessNumber: String,
      signatureCertificate: Bool
    ) async -> Outcome {
      let slot: CertificateSlot =
        signatureCertificate ? .qualifiedSignature : .authentication
      return await withCard(cardAccessNumber: cardAccessNumber) { operations in
        do {
          return .result(try operations.readCertificate(slot))
        } catch {
          return .refusedBeforeCredentialTransmit(.certificateUnavailable)
        }
      }
    }

    internal static func browserAuthentication(
      cardAccessNumber: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) async -> Outcome {
      await sign(
        cardAccessNumber: cardAccessNumber,
        documentPin2: nil,
        role: .pin1,
        slot: .authentication,
        keyProfile: keyProfile,
        algorithm: algorithm,
        digest: digest,
        qualified: false
      )
    }

    internal static func signDocument(
      cardAccessNumber: String,
      pin2: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) async -> Outcome {
      await sign(
        cardAccessNumber: cardAccessNumber,
        documentPin2: pin2,
        role: .pin2,
        slot: .qualifiedSignature,
        keyProfile: keyProfile,
        algorithm: algorithm,
        digest: digest,
        qualified: true
      )
    }

    private static func sign(
      cardAccessNumber: String,
      documentPin2: String?,
      role: CredentialRole,
      slot: CertificateSlot,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data,
      qualified: Bool
    ) async -> Outcome {
      await withCard(cardAccessNumber: cardAccessNumber) { operations in
        guard
          let identity = identity(
            operations: operations,
            slot: slot,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: digest
          )
        else {
          return .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch)
        }

        let probe: RetryProbeOutcome
        do {
          probe = try operations.probeRetryCounter(role: role)
        } catch {
          return .refusedBeforeCredentialTransmit(
            .retryFloor(role, .refuseUnreadable)
          )
        }
        switch probe {
        case .locked:
          return .refusedBeforeCredentialTransmit(.credentialBlocked(role))
        case .invalidated:
          return .refusedBeforeCredentialTransmit(.credentialInvalidated(role))
        case .remaining, .verified:
          let verdict = RetryFloor.evaluate(probeOutcome: probe)
          guard verdict == .proceed else {
            return .refusedBeforeCredentialTransmit(.retryFloor(role, verdict))
          }
        case .noInformation, .other:
          return .refusedBeforeCredentialTransmit(
            .retryFloor(role, .refuseUnreadable)
          )
        }

        let verified: Outcome?
        switch role {
        case .pin1:
          guard let pin = CardCredentialStore.pin1() else {
            return .refusedBeforeCredentialTransmit(.invalidCredential(role))
          }
          verified = verifyPin1(pin, with: operations)
        case .pin2:
          guard
            let documentPin2,
            let pin = Pin2(digits: documentPin2)
          else {
            return .refusedBeforeCredentialTransmit(.invalidCredential(role))
          }
          verified = verifyPin2(pin, with: operations)
        case .puk:
          return .refusedBeforeCredentialTransmit(.invalidCredential(role))
        }
        if let verified { return verified }

        do {
          let raw =
            try qualified
            ? operations.computeQualifiedSignature(
              overDigest: identity.request.digest,
              algorithm: identity.request.algorithm,
              expectedSignatureLength: identity.request.expectedSignatureLength
            )
            : operations.computeAuthenticationSignature(
              overDigest: identity.request.digest,
              algorithm: identity.request.algorithm,
              expectedSignatureLength: identity.request.expectedSignatureLength
            )
          guard
            let signature = identity.request.wireSignature(from: raw),
            identity.request.isSatisfied(by: signature, from: identity.publicKey)
          else {
            return .completionAmbiguous
          }
          return .result(signature)
        } catch {
          return .completionAmbiguous
        }
      }
    }

    /// Nil means VERIFY succeeded.
    ///
    /// Every other value is terminal for this operation and no caller
    /// may automatically resend the PIN.
    private static func verifyPin1(
      _ pin: consuming Pin1,
      with operations: CardOperations
    ) -> Outcome? {
      do {
        try operations.verifyPin1(pin.consumeForSingleTransmission())
        return nil
      } catch CardOperationError.pinRejected(let remaining) {
        return .rejected(.credential(.pin1, remaining: remaining))
      } catch CardOperationError.pinBlocked {
        return .rejected(.credential(.pin1, remaining: nil))
      } catch CardOperationError.credentialInvalidated {
        return .rejected(.credential(.pin1, remaining: nil))
      } catch {
        return .completionAmbiguous
      }
    }

    /// PIN2 sibling of `verifyPin1`; kept separate so the type system cannot
    /// route one role's credential into the other role's command.
    private static func verifyPin2(
      _ pin: consuming Pin2,
      with operations: CardOperations
    ) -> Outcome? {
      do {
        try operations.verifyPin2(pin.consumeForSingleTransmission())
        return nil
      } catch CardOperationError.pinRejected(let remaining) {
        return .rejected(.credential(.pin2, remaining: remaining))
      } catch CardOperationError.pinBlocked {
        return .rejected(.credential(.pin2, remaining: nil))
      } catch CardOperationError.credentialInvalidated {
        return .rejected(.credential(.pin2, remaining: nil))
      } catch {
        return .completionAmbiguous
      }
    }

    private static func identity(
      operations: CardOperations,
      slot: CertificateSlot,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) -> Identity? {
      guard
        let certificateData = try? operations.readCertificate(slot),
        let certificate = SecCertificateCreateWithData(
          nil, certificateData as CFData
        ),
        let publicKey = SecCertificateCopyKey(certificate),
        CardKeyProfile.resolve(fromPublicKey: publicKey) == keyProfile.cardKeyProfile,
        let request = SignRequest.resolve(
          profile: keyProfile.cardKeyProfile,
          algorithm: algorithm.signingAlgorithm,
          digest: digest
        )
      else {
        return nil
      }
      return Identity(publicKey: publicKey, request: request)
    }

    private static func withCard(
      cardAccessNumber: String,
      _ operation: @escaping @Sendable (CardOperations) -> Outcome
    ) async -> Outcome {
      let result = await CardMaintenance.onSecureNearFieldCard(
        cardAccessNumber: cardAccessNumber,
        message: holdMessage,
        operation
      )
      switch result {
      case .connected(let outcome):
        return outcome
      case .wrongCardAccessNumber:
        return .rejected(.cardAccessNumber)
      case .failed:
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
    }
  }
#endif
