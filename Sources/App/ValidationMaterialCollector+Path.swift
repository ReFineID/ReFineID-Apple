#if os(macOS)

  import CardCore
  import Foundation
  import Security

  /// Certificate-path construction for validation-material collection.
  extension ValidationMaterialCollector {
    /// Finds an embedded or AIA issuer and verifies its certificate signature.
    internal static func issuer(
      of subject: Data,
      facts: CertificateFacts,
      at referenceDate: Date,
      collection: inout Collection,
      dependencies: Dependencies
    ) async throws -> Data {
      if let embedded = collection.candidates.first(where: { candidate in
        candidate != subject
          && Self.isDirectlyIssued(
            subject, by: candidate, at: referenceDate
          )
      }) {
        return embedded
      }
      for address in Self.boundedCertificateAddresses(
        facts.issuerCertificateUrls
      ) {
        guard
          let body = try? await dependencies.get(address, false),
          let candidate = Self.certificate(from: body),
          Self.isDirectlyIssued(subject, by: candidate, at: referenceDate)
        else { continue }
        collection.addCandidate(candidate)
        return candidate
      }
      throw Failure.issuerUnavailable
    }

    /// Whether one certificate is directly signed by another at a date.
    private static func isDirectlyIssued(
      _ subject: Data,
      by issuer: Data,
      at date: Date
    ) -> Bool {
      guard
        let subjectCertificate = SecCertificateCreateWithData(
          nil, subject as CFData
        ),
        let issuerCertificate = SecCertificateCreateWithData(
          nil, issuer as CFData
        )
      else { return false }
      var trust: SecTrust?
      guard
        SecTrustCreateWithCertificates(
          [subjectCertificate, issuerCertificate] as CFArray,
          SecPolicyCreateBasicX509(),
          &trust
        ) == errSecSuccess,
        let trust,
        SecTrustSetAnchorCertificates(
          trust, [issuerCertificate] as CFArray
        ) == errSecSuccess,
        SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
        SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
        SecTrustSetVerifyDate(trust, date as CFDate) == errSecSuccess
      else { return false }
      var error: CFError?
      return SecTrustEvaluateWithError(trust, &error)
    }

    /// PEM unwrapped to one DER certificate, or DER unchanged.
    private static func certificate(from body: Data) -> Data? {
      if SecCertificateCreateWithData(nil, body as CFData) != nil {
        return body
      }
      guard let text = String(data: body, encoding: .ascii) else { return nil }
      let base64 =
        text
        .split(whereSeparator: \.isNewline)
        .filter { !$0.hasPrefix("-----") }
        .joined()
      guard
        let decoded = Data(base64Encoded: String(base64)),
        SecCertificateCreateWithData(nil, decoded as CFData) != nil
      else { return nil }
      return decoded
    }
  }

#endif
