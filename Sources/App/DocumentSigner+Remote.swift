// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import CardCore
  import CryptoKit
  import Foundation
  import Security

  extension DocumentSigner {
    private enum RemoteSigningPolicy {
      static let maximumCertificateAttempts = 3
      static let retryDelaySeconds: TimeInterval = 0.25
    }

    /// A selected RAPP phone is the signing device only when no local reader
    /// card is ready.
    ///
    /// The two paths never silently retry one another after an
    /// authenticated or credential-bearing operation has begun.
    @MainActor internal static var usesRappSigning: Bool {
      !SupportedCardTransports.offersNearField
        && !CardPresence.shared.isReaderCardReady
        && (try? RappDeviceVault().selectedPairID()) != nil
    }

    /// Builds the same locally verified card material as the reader path while
    /// delegating only the certificate read and PIN 2 card signature to the
    /// explicitly paired phone.
    internal static func remoteCardMaterial(
      prepared: PdfSignaturePlaceholder,
      byteRangeDigest: Data,
      expectedCertificate: Data?
    ) async throws -> CardMaterial {
      let product = try await Self.remoteQualifiedSignature(
        documentName: String(
          localized: "Document",
          defaultValue: "Document",
          table: "DocumentSigning"
        ),
        expectedCertificate: expectedCertificate
      ) { certificate in
        QualifiedDocumentCms.signedAttributes(
          byteRangeDigest: byteRangeDigest,
          signerCertificate: certificate
        )
      }
      return CardMaterial(
        placeholder: prepared,
        signedAttributes: product.content,
        signature: product.signature,
        certificate: product.certificate,
        profile: product.profile
      )
    }

    /// Fetches the qualified signature certificate from the paired phone with retries.
    private static func fetchRemoteSignatureCertificate(
      displayName: String
    ) throws -> Data {
      var certificate: Data?
      var certificateError: Error?
      for attempt in 1...RemoteSigningPolicy.maximumCertificateAttempts {
        do {
          let certificateClient = RappPersistentRequesterClient(displayName: displayName)
          let certificateResponse = try certificateClient.perform(.readSignatureCertificate)
          if case .signatureCertificate(let cert) = certificateResponse {
            certificate = cert
            break
          }
        } catch {
          certificateError = error
          if attempt < RemoteSigningPolicy.maximumCertificateAttempts {
            Thread.sleep(forTimeInterval: RemoteSigningPolicy.retryDelaySeconds)
          }
        }
      }
      guard let certificate else {
        throw certificateError ?? Failure.card(.failed)
      }
      return certificate
    }

    /// Performs one remote qualified-signature operation.
    ///
    /// The requester sends only the digest and public algorithm metadata;
    /// PIN 2 exists solely in the phone authorization UI and its NFC card
    /// session.
    internal static func remoteQualifiedSignature(
      documentName: String,
      expectedCertificate: Data?,
      content: @escaping @Sendable (Data) -> Data
    ) async throws -> CardMaintenance.QualifiedProduct {
      try await Task.detached(priority: .userInitiated) {
        try Self.executeRemoteQualifiedSignature(
          documentName: documentName,
          expectedCertificate: expectedCertificate,
          content: content)
      }.value
    }

    private static func executeRemoteQualifiedSignature(
      documentName: String,
      expectedCertificate: Data?,
      content: (Data) -> Data
    ) throws -> CardMaintenance.QualifiedProduct {
      let displayName = ProcessInfo.processInfo.hostName
      let certificate = try Self.fetchRemoteSignatureCertificate(displayName: displayName)
      guard
        CardMaintenance.qualifiedCertificate(
          certificate, matches: expectedCertificate
        )
      else {
        throw Failure.stampSignerChanged
      }
      guard
        let securityCertificate = SecCertificateCreateWithData(
          nil, certificate as CFData
        ),
        let publicKey = SecCertificateCopyKey(securityCertificate),
        let profile = CardKeyProfile.resolve(fromPublicKey: publicKey)
      else {
        throw Failure.card(.failed)
      }

      let signedContent = content(certificate)
      let digest = Data(SHA384.hash(data: signedContent))
      guard
        let request = profile.qualifiedDocumentRequest(digest: digest),
        let remoteAlgorithm = RappOperationDriver.SignatureAlgorithm(request.algorithm)
      else {
        throw Failure.card(.failed)
      }

      let signingClient = RappPersistentRequesterClient(displayName: displayName)
      let signatureResponse = try signingClient.perform(
        .documentSigning(
          documentName: documentName,
          keyProfile: RappOperationDriver.KeyProfile(profile),
          algorithm: remoteAlgorithm,
          digest: digest
        )
      )
      guard
        case .signature(let signature) = signatureResponse,
        request.isSatisfied(by: signature, from: publicKey)
      else {
        throw Failure.card(.failed)
      }
      return CardMaintenance.QualifiedProduct(
        signature: signature,
        content: signedContent,
        certificate: certificate,
        profile: profile
      )
    }
  }

#endif
