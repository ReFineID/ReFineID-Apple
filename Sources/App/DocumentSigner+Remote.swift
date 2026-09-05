// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import Security

extension DocumentSigner {
  private enum RemoteSigningPolicy {
    static let maximumCertificateAttempts = 3
    static let maximumSigningAttempts = 3
    static let retryDelaySeconds: TimeInterval = 0.25
    static let settleDelaySeconds: TimeInterval = 0.25
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
      } catch let error as RappRequesterClientError {
        certificateError = error
        guard Self.isRecoverableRemoteError(error),
          attempt < RemoteSigningPolicy.maximumCertificateAttempts
        else {
          throw error
        }
        Thread.sleep(forTimeInterval: RemoteSigningPolicy.retryDelaySeconds)
      } catch {
        throw error
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
    Thread.sleep(forTimeInterval: RemoteSigningPolicy.settleDelaySeconds)
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

    let signature = try Self.executeRemoteDocumentSigning(
      displayName: displayName,
      documentName: documentName,
      keyProfile: RappOperationDriver.KeyProfile(profile),
      algorithm: remoteAlgorithm,
      digest: digest
    )
    guard request.isSatisfied(by: signature, from: publicKey) else {
      throw Failure.card(.failed)
    }
    return CardMaintenance.QualifiedProduct(
      signature: signature,
      content: signedContent,
      certificate: certificate,
      profile: profile
    )
  }

  /// Sends the document signing request to the paired phone, retrying transparently
  /// when the transport connection drops or the peer was not found before authorization.
  private static func executeRemoteDocumentSigning(
    displayName: String,
    documentName: String,
    keyProfile: RappOperationDriver.KeyProfile,
    algorithm: RappOperationDriver.SignatureAlgorithm,
    digest: Data
  ) throws -> Data {
    var signingError: Error?
    for attempt in 1...RemoteSigningPolicy.maximumSigningAttempts {
      do {
        let signingClient = RappPersistentRequesterClient(displayName: displayName)
        let signatureResponse = try signingClient.perform(
          .documentSigning(
            documentName: documentName,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: digest
          )
        )
        if case .signature(let signature) = signatureResponse {
          return signature
        }
        throw Failure.card(.failed)
      } catch let error as RappRequesterClientError {
        signingError = error
        guard Self.isRecoverableRemoteError(error),
          attempt < RemoteSigningPolicy.maximumSigningAttempts
        else {
          throw error
        }
        Thread.sleep(forTimeInterval: RemoteSigningPolicy.retryDelaySeconds)
      } catch {
        throw error
      }
    }
    guard let signingError else { throw Failure.card(.failed) }
    throw signingError
  }

  private static func isRecoverableRemoteError(_ error: RappRequesterClientError) -> Bool {
    switch error {
    case .transport, .peerNotFound:
      true

    case .noActivePair, .noSelectedPair, .protocolFailure, .terminal, .timedOut,
      .unexpectedResult:
      false
    }
  }
}
