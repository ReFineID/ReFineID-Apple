// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_SLIM_RELAY && REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation

  /// Reaches the card for one slim-relay request.
  ///
  /// The certificate is answered from what this device already read while
  /// setting its own identity up, so a peer asking for it does not cost the
  /// holder a card hold. A signature has to reach the card, because only the
  /// card holds the key.
  internal enum SlimCardWork {
    /// Performs `request` and names what came back.
    internal static func perform(
      _ request: PersistentRelayMessage
    ) async -> PersistentRelayMessage {
      switch request {
      case .identityRequest(let id):
        guard let primed = PrimeStore.primedAuthenticationCertificates().first else {
          return .failure(id: id, reason: .cardUnavailable)
        }
        return .identityResponse(id: id, certificateDER: primed)

      case .signatureRequest(let id, let profile, let algorithm, let digest):
        return await sign(id: id, profile: profile, algorithm: algorithm, digest: digest)

      case .failure, .identityResponse, .signatureResponse:
        return .failure(id: request.requestID, reason: .unsupportedAlgorithm)
      }
    }

    private static func sign(
      id: UUID,
      profile: PersistentRelayCardProfile,
      algorithm: PersistentRelaySigningAlgorithm,
      digest: Data
    ) async -> PersistentRelayMessage {
      guard let accessNumber = CardCredentialStore.displayedCardAccessNumber() else {
        return .failure(id: id, reason: .missingCardAccessNumber)
      }
      guard
        let relayAlgorithm = RappOperationDriver.SignatureAlgorithm(algorithm.signingAlgorithm)
      else {
        return .failure(id: id, reason: .unsupportedAlgorithm)
      }
      let outcome = await RappNfcCardExecutor.browserAuthentication(
        cardAccessNumber: accessNumber,
        keyProfile: RappOperationDriver.KeyProfile(profile.cardKeyProfile),
        algorithm: relayAlgorithm,
        digest: digest
      )
      switch outcome {
      case .result(let signature):
        return .signatureResponse(id: id, signature: signature)
      case .rejected(.cardAccessNumber):
        return .failure(id: id, reason: .wrongCardAccessNumber)
      case .rejected:
        return .failure(id: id, reason: .pin1Rejected(remaining: nil))
      case .refusedBeforeCredentialTransmit:
        return .failure(id: id, reason: .cardUnavailable)
      case .completionAmbiguous:
        return .failure(id: id, reason: .communication)
      }
    }
  }

#endif
