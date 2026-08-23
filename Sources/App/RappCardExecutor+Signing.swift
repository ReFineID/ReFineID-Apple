// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS) && REFINEID_REMOTE_CARD
import CardCore
import Foundation
import Security

extension RappCardExecutor {
    private struct SignParameters {
        let cardAccessNumber: String?
        let documentPin1: String?
        let documentPin2: String?
        let role: CredentialRole
        let slot: CertificateSlot
        let keyProfile: RappOperationDriver.KeyProfile
        let algorithm: RappOperationDriver.SignatureAlgorithm
        let digest: Data
        let qualified: Bool
    }

    internal static func browserAuthentication(
        cardAccessNumber: String?,
        keyProfile: RappOperationDriver.KeyProfile,
        algorithm: RappOperationDriver.SignatureAlgorithm,
        digest: Data
    ) async -> Outcome {
        await browserAuthentication(
            cardAccessNumber: cardAccessNumber,
            pin1: nil,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: digest
        )
    }

    internal static func browserAuthentication(
        cardAccessNumber: String?,
        pin1: String?,
        keyProfile: RappOperationDriver.KeyProfile,
        algorithm: RappOperationDriver.SignatureAlgorithm,
        digest: Data
    ) async -> Outcome {
        await sign(
            SignParameters(
                cardAccessNumber: cardAccessNumber,
                documentPin1: pin1,
                documentPin2: nil,
                role: .pin1,
                slot: .authentication,
                keyProfile: keyProfile,
                algorithm: algorithm,
                digest: digest,
                qualified: false
            )
        )
    }

    internal static func signDocument(
        cardAccessNumber: String?,
        pin2: String,
        keyProfile: RappOperationDriver.KeyProfile,
        algorithm: RappOperationDriver.SignatureAlgorithm,
        digest: Data
    ) async -> Outcome {
        await sign(
            SignParameters(
                cardAccessNumber: cardAccessNumber,
                documentPin1: nil,
                documentPin2: pin2,
                role: .pin2,
                slot: .qualifiedSignature,
                keyProfile: keyProfile,
                algorithm: algorithm,
                digest: digest,
                qualified: true
            )
        )
    }

    private static func sign(
        _ params: SignParameters
    ) async -> Outcome {
        await withCard(cardAccessNumber: params.cardAccessNumber) { operations in
            executeSign(params, with: operations)
        }
    }

    private static func executeSign(
        _ params: SignParameters,
        with operations: CardOperations
    ) -> Outcome {
        guard
            let identity = identity(
                operations: operations,
                slot: params.slot,
                keyProfile: params.keyProfile,
                algorithm: params.algorithm,
                digest: params.digest
            )
        else {
            return .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch)
        }

        if let floorRefusal = evaluateRetryFloor(operations: operations, role: params.role) {
            return .refusedBeforeCredentialTransmit(floorRefusal)
        }

        if let verificationOutcome = verifyCredential(
            role: params.role,
            documentPin1: params.documentPin1,
            documentPin2: params.documentPin2,
            operations: operations
        ) {
            return verificationOutcome
        }

        return computeAndVerifySignature(
            operations: operations,
            identity: identity,
            qualified: params.qualified
        )
    }

    private static func evaluateRetryFloor(
        operations: CardOperations,
        role: CredentialRole
    ) -> Refusal? {
        let probe: RetryProbeOutcome
        do {
            probe = try operations.probeRetryCounter(role: role)
        } catch {
            return .retryFloor(role, .refuseUnreadable)
        }
        switch probe {
        case .locked:
            return .credentialBlocked(role)

        case .invalidated:
            return .credentialInvalidated(role)

        case .remaining, .verified:
            let verdict = RetryFloor.evaluate(probeOutcome: probe)
            return verdict == .proceed ? nil : .retryFloor(role, verdict)

        case .noInformation, .other:
            return .retryFloor(role, .refuseUnreadable)
        }
    }

    private static func verifyCredential(
        role: CredentialRole,
        documentPin1: String?,
        documentPin2: String?,
        operations: CardOperations
    ) -> Outcome? {
        switch role {
        case .pin1:
            let pin: Pin1?
            if let documentPin1 {
                pin = Pin1(digits: documentPin1)
            } else {
                pin = CardCredentialStore.pin1()
            }
            guard let pin else {
                return .refusedBeforeCredentialTransmit(.invalidCredential(role))
            }
            return verifyPin1(pin, with: operations)

        case .pin2:
            guard
                let documentPin2,
                let pin = Pin2(digits: documentPin2)
            else {
                return .refusedBeforeCredentialTransmit(.invalidCredential(role))
            }
            return verifyPin2(pin, with: operations)

        case .puk:
            return .refusedBeforeCredentialTransmit(.invalidCredential(role))
        }
    }

    private static func computeAndVerifySignature(
        operations: CardOperations,
        identity: Identity,
        qualified: Bool
    ) -> Outcome {
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
}
#endif
