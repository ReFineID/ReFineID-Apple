#if os(macOS)

  import CardCore
  import Foundation

  /// Collects what a validator needs to judge the signature after the
  /// signing certificates have expired: the issuer chain, and proof
  /// each link was good when it signed (ETSI EN 319 142-1 long-term
  /// level).
  ///
  /// The walk is deliberately forgiving in one direction and strict in
  /// the other. A certificate kept without its revocation answer still
  /// helps a validator close the chain, so a failed step keeps what it
  /// found; but a responder saying "revoked" ends the signing, because
  /// a signature nobody should trust is worse than no signature.
  internal enum ValidationMaterialCollector {
    /// How many issuers up a chain may go before it is called broken.
    private static let maximumDepth = 8

    /// Everything reachable from the signer certificate.
    internal static func collect(
      signerCertificate: Data
    ) async -> PdfValidationStore.Material {
      var certificates: [Data] = []
      var responses: [Data] = []
      var current = signerCertificate

      for _ in 0..<Self.maximumDepth {
        guard let facts = CertificateFacts(der: current), !facts.isSelfIssued
        else {
          break
        }
        guard
          let issuerUrl = facts.issuerCertificateUrls.first,
          let issuerDer = try? await Self.certificate(from: issuerUrl),
          let issuerFacts = CertificateFacts(der: issuerDer)
        else {
          break
        }
        if !certificates.contains(issuerDer) {
          certificates.append(issuerDer)
        }
        if let responder = facts.ocspUrls.first,
          let response = try? await Self.status(
            of: facts, under: issuerFacts, from: responder
          )
        {
          responses.append(response)
        }
        // A root signs itself; stopping here keeps the anchor out of
        // the store, where a validator supplies its own.
        if issuerFacts.isSelfIssued {
          break
        }
        current = issuerDer
      }
      // No revocation lists: every authority in the chain publishes a
      // responder, and a distribution-point fetch would be untested
      // code on a path that decides whether a signature is archival.
      return PdfValidationStore.Material(
        certificates: certificates,
        ocspResponses: responses,
        revocationLists: []
      )
    }

    /// One issuer certificate, DER or PEM as published.
    private static func certificate(from address: String) async throws -> Data {
      let body = try await SigningNetwork.get(address, allowingListSize: false)
      return Self.derFromPossiblePem(body)
    }

    /// One OCSP answer about `subject`.
    private static func status(
      of subject: CertificateFacts,
      under issuer: CertificateFacts,
      from responder: String
    ) async throws -> Data {
      var nonce = Data(count: OcspRequest.nonceByteCount)
      nonce.withUnsafeMutableBytes { buffer in
        if let base = buffer.baseAddress {
          _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
      }
      let request = OcspRequest.encoded(
        issuerName: subject.issuerName,
        issuerKey: issuer.publicKeyBits,
        serial: subject.serialNumber,
        nonce: nonce
      )
      return try await SigningNetwork.post(
        request,
        to: responder,
        contentType: "application/ocsp-request",
        credentials: nil
      )
    }

    /// PEM unwrapped to DER, or the bytes unchanged when already DER.
    ///
    /// Authorities publish `.crt` URLs in both encodings, sometimes
    /// contradicting their own content type.
    private static func derFromPossiblePem(_ body: Data) -> Data {
      guard body.first == DerValues.sequenceTagByte else {
        let text = String(bytes: body, encoding: .ascii) ?? ""
        var stripped = text.replacingOccurrences(
          of: "-----BEGIN CERTIFICATE-----", with: ""
        )
        stripped = stripped.replacingOccurrences(
          of: "-----END CERTIFICATE-----", with: ""
        )
        let base64 = stripped.filter { character in !character.isWhitespace }
        return Data(base64Encoded: base64) ?? body
      }
      return body
    }
  }

#endif
