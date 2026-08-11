// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if os(macOS)

  import Foundation
  import Security

  /// Cryptographically verifies an RFC 3161 TimeStampToken on macOS.
  ///
  /// CMSDecoder verifies the signed attributes, content digest,
  /// SignerIdentifier and signature. The remaining RFC 3161 rules are
  /// checked explicitly: one signer, ESS certificate binding, the
  /// critical timestamping-only EKU, certificate validity at genTime,
  /// and a path ending at one of the caller's trusted certificates.
  public enum TimestampTokenVerifier {
    /// Authenticated CMS state needed for certificate-policy checks.
    private struct AuthenticatedCms {
      let decoder: CMSDecoder
      let signerCertificate: Data
      let trust: SecTrust
    }

    /// A token whose signature and timestamp signer were verified.
    public struct VerifiedToken: Equatable {
      /// The token exactly as received.
      public let token: Data

      /// The certificate selected by the CMS SignerIdentifier.
      public let signerCertificate: Data

      /// Every certificate embedded in SignedData.
      public let embeddedCertificates: [Data]

      /// The exact certificate path Security authenticated under the
      /// exclusive anchors in force for the verification.
      public let verifiedCertificateChain: [Data]

      /// The anchor certificate that terminated the authenticated path.
      public let trustedCertificate: Data

      /// The signed TSTInfo generation time.
      public let generatedAt: Date
    }

    /// Why a token could not be authenticated.
    public enum Failure: Error, Equatable {
      /// CMS signed-attribute, digest, or signature verification failed.
      case invalidSignature

      /// The signer certificate is not restricted to timestamping by
      /// one critical extended-key-usage extension.
      case invalidTimestampingCertificate

      /// The CMS or its encapsulated content is malformed or ambiguous.
      case malformed

      /// No embedded certificate matches the CMS SignerIdentifier.
      case signerCertificateMissing

      /// The signed ESS certificate reference does not identify the
      /// CMS signer certificate.
      case signingCertificateMismatch

      /// The signer did not build to one of the supplied trust
      /// certificates at the token's generation time.
      case untrustedSigner
    }

    /// Verifies `token` against the certificate chain it itself
    /// carries.
    ///
    /// The authority is trusted as configured: the caller decided whom
    /// to ask, so the token's own certificate set is the anchor set.
    /// Self-issued embedded certificates are preferred as anchors, so
    /// the verified path runs as deep as the token allows.
    public static func verify(_ token: Data) throws -> VerifiedToken {
      try Self.verify(token, trustedCertificates: Self.selfAnchors(in: token))
    }

    /// Verifies `token` under the supplied certificates.
    ///
    /// The trusted certificates are exclusive anchors. Passing an
    /// empty array fails closed; it never falls back to the system
    /// root store.
    public static func verify(
      _ token: Data,
      trustedCertificates: [Data]
    ) throws -> VerifiedToken {
      let contents: RfcTimestamp.TokenContents
      do {
        contents = try RfcTimestamp.contents(in: token)
      } catch {
        throw Failure.malformed
      }

      let authenticated = try Self.authenticatedCms(
        token: token, expectedContent: contents.tstInfo
      )
      try Self.verifyCertificateBinding(
        token: token, certificate: authenticated.signerCertificate
      )
      guard
        Self.signerCertificateIsValid(
          authenticated.signerCertificate, at: contents.generatedAt
        )
      else {
        throw Failure.invalidTimestampingCertificate
      }
      let verifiedChain = try Self.evaluate(
        authenticated.trust,
        trustedCertificates: trustedCertificates,
        at: contents.generatedAt
      )
      guard let trustedCertificate = verifiedChain.last else {
        throw Failure.untrustedSigner
      }

      return VerifiedToken(
        token: token,
        signerCertificate: authenticated.signerCertificate,
        embeddedCertificates: try Self.certificates(
          from: authenticated.decoder
        ),
        verifiedCertificateChain: verifiedChain,
        trustedCertificate: trustedCertificate,
        generatedAt: contents.generatedAt
      )
    }

    /// The token's own anchor candidates: its self-issued embedded
    /// certificates, or every embedded certificate when none is.
    private static func selfAnchors(in token: Data) throws -> [Data] {
      let embedded = try Self.certificates(from: Self.decoder(for: token))
      let selfIssued = embedded.filter(Self.isSelfIssued)
      return selfIssued.isEmpty ? embedded : selfIssued
    }

    /// Whether a certificate names itself as its issuer.
    private static func isSelfIssued(_ certificate: Data) -> Bool {
      guard
        let parsed = SecCertificateCreateWithData(nil, certificate as CFData),
        let subject = SecCertificateCopyNormalizedSubjectSequence(parsed),
        let issuer = SecCertificateCopyNormalizedIssuerSequence(parsed)
      else { return false }
      return (subject as Data) == (issuer as Data)
    }

    /// A CMS whose content and sole signature are authenticated.
    private static func authenticatedCms(
      token: Data,
      expectedContent: Data
    ) throws -> AuthenticatedCms {
      let decoder = try Self.decoder(for: token)
      guard try Self.content(from: decoder) == expectedContent else {
        throw Failure.malformed
      }
      let trust = try Self.authenticatedTrust(from: decoder)
      var signer: SecCertificate?
      guard
        CMSDecoderCopySignerCert(decoder, 0, &signer) == errSecSuccess,
        let signer
      else {
        throw Failure.signerCertificateMissing
      }
      return AuthenticatedCms(
        decoder: decoder,
        signerCertificate: SecCertificateCopyData(signer) as Data,
        trust: trust
      )
    }

    /// Signature authentication and trust object for the sole signer.
    private static func authenticatedTrust(
      from decoder: CMSDecoder
    ) throws -> SecTrust {
      var signerCount = 0
      guard
        CMSDecoderGetNumSigners(decoder, &signerCount) == errSecSuccess,
        signerCount == 1,
        let policy = SecPolicyCreateWithProperties(
          kSecPolicyAppleTimeStamping, nil
        )
      else {
        throw Failure.malformed
      }
      var signerStatus = CMSSignerStatus.unsigned
      var trust: SecTrust?
      guard
        CMSDecoderCopySignerStatus(
          decoder, 0, policy, false, &signerStatus, &trust, nil
        ) == errSecSuccess
      else {
        throw Failure.malformed
      }
      guard signerStatus == .valid else {
        throw Self.failure(for: signerStatus)
      }
      guard let trust else { throw Failure.signerCertificateMissing }
      return trust
    }

    /// The public verifier error corresponding to a CMS signer status.
    private static func failure(for status: CMSSignerStatus) -> Failure {
      switch status {
      case .invalidSignature:
        return .invalidSignature
      case .needsDetachedContent:
        return .malformed
      default:
        return .signerCertificateMissing
      }
    }

    /// ESS hash binding and the RFC 3161 timestamping-only EKU.
    private static func verifyCertificateBinding(
      token: Data,
      certificate: Data
    ) throws {
      do {
        try CmsSigningCertificate.verify(
          token: token, certificate: certificate
        )
      } catch {
        throw Failure.signingCertificateMismatch
      }
      guard
        Self.signerCertificateProfileIsValid(certificate)
      else {
        throw Failure.invalidTimestampingCertificate
      }
    }

    /// Timestamp signer profile checks that must hold even when the leaf is
    /// itself an exclusive caller-supplied trust anchor.
    internal static func signerCertificateProfileIsValid(
      _ certificate: Data
    ) -> Bool {
      CertificateFacts(der: certificate)?.isPermittedTimestampSigner == true
    }

    /// Verifies the signer's own X.509 validity interval at the signed
    /// TSTInfo generation time, not at the device's current wall clock.
    internal static func signerCertificateIsValid(
      _ certificate: Data,
      at generatedAt: Date
    ) -> Bool {
      guard
        let signer = SecCertificateCreateWithData(nil, certificate as CFData),
        let notBefore = SecCertificateCopyNotValidBeforeDate(signer) as Date?,
        let notAfter = SecCertificateCopyNotValidAfterDate(signer) as Date?
      else { return false }
      return notBefore <= generatedAt && generatedAt <= notAfter
    }

    /// Evaluates signer trust at genTime under exclusive caller anchors.
    private static func evaluate(
      _ trust: SecTrust,
      trustedCertificates: [Data],
      at generatedAt: Date
    ) throws -> [Data] {
      let anchors = trustedCertificates.compactMap { encoded in
        SecCertificateCreateWithData(nil, encoded as CFData)
      }
      guard !anchors.isEmpty, anchors.count == trustedCertificates.count else {
        throw Failure.untrustedSigner
      }
      guard
        SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
        SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
        SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
        SecTrustSetVerifyDate(trust, generatedAt as CFDate) == errSecSuccess
      else {
        throw Failure.untrustedSigner
      }
      var trustError: CFError?
      guard SecTrustEvaluateWithError(trust, &trustError) else {
        throw Failure.untrustedSigner
      }
      guard
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
      else {
        throw Failure.untrustedSigner
      }
      let encoded = chain.map { SecCertificateCopyData($0) as Data }
      guard
        let terminal = encoded.last,
        trustedCertificates.contains(terminal)
      else {
        throw Failure.untrustedSigner
      }
      return encoded
    }

    /// A finalized CMS decoder for one token.
    private static func decoder(for token: Data) throws -> CMSDecoder {
      var created: CMSDecoder?
      guard CMSDecoderCreate(&created) == errSecSuccess, let created else {
        throw Failure.malformed
      }
      let update = token.withUnsafeBytes { bytes -> OSStatus in
        guard let base = bytes.baseAddress else { return errSecParam }
        return CMSDecoderUpdateMessage(created, base, bytes.count)
      }
      guard
        update == errSecSuccess,
        CMSDecoderFinalizeMessage(created) == errSecSuccess
      else {
        throw Failure.malformed
      }
      return created
    }

    /// The embedded content, also supplied back to CMSDecoder so it
    /// computes the digest for a non-id-data content type.
    private static func content(from decoder: CMSDecoder) throws -> Data {
      var copied: CFData?
      guard
        CMSDecoderCopyContent(decoder, &copied) == errSecSuccess,
        let copied,
        CMSDecoderSetDetachedContent(decoder, copied) == errSecSuccess
      else {
        throw Failure.malformed
      }
      return copied as Data
    }

    /// The SignedData certificate set in its decoded order.
    private static func certificates(from decoder: CMSDecoder) throws -> [Data] {
      var copied: CFArray?
      guard CMSDecoderCopyAllCerts(decoder, &copied) == errSecSuccess else {
        throw Failure.malformed
      }
      guard let certificates = copied as? [SecCertificate] else { return [] }
      return certificates.map { certificate in
        SecCertificateCopyData(certificate) as Data
      }
    }
  }

#endif
