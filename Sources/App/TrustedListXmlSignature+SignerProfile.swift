#if os(macOS)

  import CardCore
  import Foundation
  import Security

  extension TrustedListXmlSignature {
    /// The signed XAdES identity and time of the cryptographic signer.
    internal struct SignerBinding {
      internal let algorithm: DigestAlgorithm
      internal let certificateDigest: Data
      internal let signingTime: Date
    }

    /// Reads the one SigningCertificateV2 binding used by current EU lists.
    internal static func signerBinding(
      in properties: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws -> SignerBinding {
      let signedSignatureProperties = try Self.soleChild(
        name: "SignedSignatureProperties",
        namespace: Xml.xadesNamespace,
        of: properties,
        document: document
      )
      let signingTimeNode = try Self.soleChild(
        name: "SigningTime",
        namespace: Xml.xadesNamespace,
        of: signedSignatureProperties,
        document: document
      )
      let signingCertificates = try Self.soleChild(
        name: "SigningCertificateV2",
        namespace: Xml.xadesNamespace,
        of: signedSignatureProperties,
        document: document
      )
      guard
        document.children(of: signingTimeNode).isEmpty,
        let signingTime = Self.date(document.text(of: signingTimeNode))
      else { throw Failure.malformed }
      let certificate = try Self.soleChild(
        name: "Cert",
        namespace: Xml.xadesNamespace,
        of: signingCertificates,
        document: document
      )
      guard document.children(of: signingCertificates).count == 1 else {
        throw Failure.malformed
      }
      let digest = try Self.soleChild(
        name: "CertDigest",
        namespace: Xml.xadesNamespace,
        of: certificate,
        document: document
      )
      try Self.checkOptionalIssuerSerial(
        in: certificate,
        digest: digest,
        document: document
      )
      return try Self.signerBinding(
        in: digest,
        signingTime: signingTime,
        document: document
      )
    }

    /// Parses CertDigest's exact two-child XMLDSig shape.
    private static func signerBinding(
      in digest: TrustedListXmlDocument.Node,
      signingTime: Date,
      document: TrustedListXmlDocument
    ) throws -> SignerBinding {
      let method = try Self.soleChild(
        name: "DigestMethod",
        namespace: Xml.signatureNamespace,
        of: digest,
        document: document
      )
      let value = try Self.soleChild(
        name: "DigestValue",
        namespace: Xml.signatureNamespace,
        of: digest,
        document: document
      )
      guard
        document.children(of: digest).count == Limits.xadesDigestChildCount,
        document.children(of: method).isEmpty,
        document.children(of: value).isEmpty
      else { throw Failure.malformed }
      let algorithm: DigestAlgorithm
      switch document.attribute("Algorithm", of: method) {
      case Xml.digestSha256:
        algorithm = .sha256
      case Xml.digestSha512:
        algorithm = .sha512
      default:
        throw Failure.unsupportedAlgorithm
      }
      guard
        let certificateDigest = Self.base64(document.text(of: value)),
        certificateDigest.count == Self.digestLength(for: algorithm)
      else { throw Failure.malformed }
      return SignerBinding(
        algorithm: algorithm,
        certificateDigest: certificateDigest,
        signingTime: signingTime
      )
    }

    /// Current lists either omit IssuerSerialV2 or carry exactly one.
    private static func checkOptionalIssuerSerial(
      in certificate: TrustedListXmlDocument.Node,
      digest: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws {
      let children = document.children(of: certificate)
      let issuers = children.filter { child in
        document.matches(
          child,
          name: "IssuerSerialV2",
          namespace: Xml.xadesNamespace
        )
      }
      guard
        issuers.count <= 1,
        children.count == 1 + issuers.count,
        children.contains(where: { child in child == digest })
      else { throw Failure.malformed }
    }

    /// Checks the signed certificate identity, validity, and signing profile.
    internal static func validateSignerProfile(
      _ encoded: Data,
      binding: SignerBinding,
      freshness: Freshness
    ) throws {
      guard
        binding.algorithm.digest(encoded) == binding.certificateDigest,
        let certificate = SecCertificateCreateWithData(nil, encoded as CFData),
        let notBefore = SecCertificateCopyNotValidBeforeDate(certificate) as Date?,
        let notAfter = SecCertificateCopyNotValidAfterDate(certificate) as Date?,
        Self.contains(freshness.issuedAt, from: notBefore, through: notAfter),
        Self.contains(binding.signingTime, from: notBefore, through: notAfter),
        CertificateFacts.isPermittedTrustedListSigner(der: encoded)
      else { throw Failure.invalidSignerProfile }
    }

    /// Whether an instant is inside X.509's inclusive validity interval.
    private static func contains(
      _ instant: Date,
      from notBefore: Date,
      through notAfter: Date
    ) -> Bool {
      instant >= notBefore && instant <= notAfter
    }

    /// Six Gregorian calendar months plus the one-hour DST publication skew.
    ///
    /// Current national lists use that skew; this is not a fixed-day substitute.
    internal static func maximumNextUpdate(after issuedAt: Date) -> Date? {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
      guard
        let sixMonths = calendar.date(
          byAdding: .month,
          value: Limits.freshnessMonthCount,
          to: issuedAt
        )
      else { return nil }
      return sixMonths.addingTimeInterval(Limits.freshnessDstTolerance)
    }
  }

#endif
