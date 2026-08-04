#if os(macOS)

  import CryptoKit
  import Foundation
  import Security

  /// The fail-closed XMLDSig boundary for ETSI trusted lists.
  internal enum TrustedListXmlSignature {
    /// XML and algorithm identifiers accepted by the boundary.
    internal enum Xml {
      internal static let canonicalization =
        "http://www.w3.org/2001/10/xml-exc-c14n#"
      internal static let digestSha256 =
        "http://www.w3.org/2001/04/xmlenc#sha256"
      internal static let digestSha512 =
        "http://www.w3.org/2001/04/xmlenc#sha512"
      internal static let envelopedTransform =
        "http://www.w3.org/2000/09/xmldsig#enveloped-signature"
      internal static let ecdsaSha256 =
        "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
      internal static let ecdsaSha512 =
        "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512"
      internal static let rsaPssSha256 =
        "http://www.w3.org/2007/05/xmldsig-more#sha256-rsa-MGF1"
      internal static let rsaPssWithParameters =
        "http://www.w3.org/2021/04/xmldsig-more#rsa-pss"
      internal static let rsaSha256 =
        "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
      internal static let rsaSha512 =
        "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"
      internal static let signatureNamespace =
        "http://www.w3.org/2000/09/xmldsig#"
      internal static let signedPropertiesType =
        "http://uri.etsi.org/01903#SignedProperties"
      internal static let trustedListNamespace =
        "http://uri.etsi.org/02231/v2#"
      internal static let xadesNamespace =
        "http://uri.etsi.org/01903/v1.3.2#"
    }

    /// Structural sizes fixed by the supported XMLDSig profiles.
    internal enum Limits {
      internal static let bitsPerByte = 8
      internal static let digestSha256Bytes = 32
      internal static let digestSha512Bytes = 64
      internal static let freshnessDstTolerance: TimeInterval = 3_600
      internal static let freshnessMonthCount = 6
      internal static let integerByteRoundingAdjustment = 7
      internal static let pssParameterCount = 4
      internal static let pssSaltBytes = 32
      internal static let referenceCount = 2
      internal static let referenceFixedChildCount = 2
      internal static let referenceTransformedChildCount = 3
      internal static let signatureComponentCount = 2
      internal static let signedInfoFixedChildCount = 2
      internal static let xadesDigestChildCount = 2
    }

    /// Why a remote trusted list is unusable.
    internal enum Failure: Error, Equatable {
      /// A signed reference no longer matches the XML.
      case invalidDigest

      /// The cryptographic SignatureValue is invalid.
      case invalidSignature

      /// The signer certificate or its signed XAdES binding is unsuitable.
      case invalidSignerProfile

      /// The XML or required XMLDSig/XAdES structure is malformed.
      case malformed

      /// The list is not currently within its issue/update interval.
      case stale

      /// The signature or digest algorithm is outside the supported set.
      case unsupportedAlgorithm

      /// No embedded signing certificate is authorized by the caller.
      case untrustedSigner

      /// Duplicate IDs or ambiguous reference targets were found.
      case wrapping
    }

    /// How a caller authenticates the XML signing certificate.
    internal enum SignerTrust {
      /// Exact DER certificates announced in an authenticated pointer.
      case certificates(Set<Data>)

      /// SHA-256 certificate fingerprints published out of band.
      case sha256Fingerprints(Set<Data>)
    }

    /// A list whose XML signature, references, signer, and dates passed.
    internal struct VerifiedDocument {
      /// When the list was issued.
      internal let issuedAt: Date

      /// When the list stops being current.
      internal let nextUpdate: Date

      /// The embedded certificate that verified SignatureValue.
      internal let signerCertificate: Data
    }

    /// Digest methods allowed on XMLDSig references.
    internal enum DigestAlgorithm: Equatable {
      case sha256
      case sha512

      /// Hashes canonical bytes.
      internal func digest(_ data: Data) -> Data {
        switch self {
        case .sha256:
          return Data(SHA256.hash(data: data))
        case .sha512:
          return Data(SHA512.hash(data: data))
        }
      }
    }

    /// Signature methods used by current EU trusted lists.
    internal enum SignatureAlgorithm: Equatable {
      case ecdsaSha256
      case ecdsaSha512
      case rsaPssSha256
      case rsaPssSha256Parameterized
      case rsaSha256
      case rsaSha512

      /// The Security framework verification operation.
      internal var securityAlgorithm: SecKeyAlgorithm {
        switch self {
        case .ecdsaSha256:
          return .ecdsaSignatureMessageX962SHA256
        case .ecdsaSha512:
          return .ecdsaSignatureMessageX962SHA512
        case .rsaPssSha256, .rsaPssSha256Parameterized:
          return .rsaSignatureMessagePSSSHA256
        case .rsaSha256:
          return .rsaSignatureMessagePKCS1v15SHA256
        case .rsaSha512:
          return .rsaSignatureMessagePKCS1v15SHA512
        }
      }
    }

    /// A parsed, still-to-be-authenticated XML signature.
    internal struct ParsedSignature {
      internal let algorithm: SignatureAlgorithm
      internal let binding: SignerBinding
      internal let certificates: [Data]
      internal let references: [Reference]
      internal let signatureValue: Data
      internal let signedInfo: TrustedListXmlDocument.Node
    }

    /// The constrained contents of one SignedInfo element.
    internal struct SignedInformation {
      internal let algorithm: SignatureAlgorithm
      internal let node: TrustedListXmlDocument.Node
      internal let referenceNodes: [TrustedListXmlDocument.Node]
      internal let references: [Reference]
    }

    /// The parsed Reference nodes and their resolved digest inputs.
    internal struct SignedReferences {
      internal let nodes: [TrustedListXmlDocument.Node]
      internal let values: [Reference]
    }

    /// The cryptographic value and certificates embedded in KeyInfo.
    internal struct KeyMaterial {
      internal let certificates: [Data]
      internal let signatureValue: Data
    }

    /// One reference target and whether its Signature subtree is removed.
    internal struct ReferenceTarget {
      internal let excludesSignature: Bool
      internal let node: TrustedListXmlDocument.Node
    }

    /// One same-document reference from SignedInfo.
    internal struct Reference {
      internal let algorithm: DigestAlgorithm
      internal let expectedDigest: Data
      internal let excludesSignature: Bool
      internal let target: TrustedListXmlDocument.Node
    }

    /// Authenticates one complete trusted-list XML document.
    internal static func verify(
      _ encoded: Data,
      trusting trust: SignerTrust,
      at validationTime: Date
    ) throws -> VerifiedDocument {
      let document = try TrustedListXmlDocument(encoded)
      let parsed = try Self.parsedSignature(in: document)
      for reference in parsed.references {
        let canonical = try document.canonicalized(
          reference.target,
          excludingSignature: reference.excludesSignature
        )
        guard
          reference.algorithm.digest(canonical)
            == reference.expectedDigest
        else {
          throw Failure.invalidDigest
        }
      }
      let signedInfo = try document.canonicalized(
        parsed.signedInfo, excludingSignature: false
      )
      let signer = try Self.verifySignature(
        parsed,
        canonicalSignedInfo: signedInfo,
        trust: trust
      )
      let freshness = try Self.freshness(
        in: document,
        at: validationTime
      )
      try Self.validateSignerProfile(
        signer,
        binding: parsed.binding,
        freshness: freshness
      )
      return VerifiedDocument(
        issuedAt: freshness.issuedAt,
        nextUpdate: freshness.nextUpdate,
        signerCertificate: signer
      )
    }

    /// Verifies SignatureValue with one uniquely authorized certificate.
    private static func verifySignature(
      _ parsed: ParsedSignature,
      canonicalSignedInfo: Data,
      trust: SignerTrust
    ) throws -> Data {
      let candidates = Set(parsed.certificates).filter { certificate in
        Self.isTrusted(certificate, by: trust)
      }
      guard !candidates.isEmpty else { throw Failure.untrustedSigner }
      var verified: [Data] = []
      for encoded in candidates {
        guard
          let certificate = SecCertificateCreateWithData(
            nil, encoded as CFData
          ),
          let key = Self.verificationKey(
            certificate: certificate,
            encoded: encoded,
            algorithm: parsed.algorithm
          ),
          SecKeyIsAlgorithmSupported(
            key, .verify, parsed.algorithm.securityAlgorithm
          )
        else {
          continue
        }
        var error: Unmanaged<CFError>?
        guard
          let signature = Self.securitySignature(
            parsed.signatureValue,
            algorithm: parsed.algorithm,
            key: key
          )
        else {
          continue
        }
        if SecKeyVerifySignature(
          key,
          parsed.algorithm.securityAlgorithm,
          canonicalSignedInfo as CFData,
          signature as CFData,
          &error
        ) {
          verified.append(encoded)
        }
      }
      guard verified.count == 1, let signer = verified.first else {
        throw Failure.invalidSignature
      }
      return signer
    }

    /// Whether a certificate is exactly authorized by the caller.
    private static func isTrusted(
      _ certificate: Data,
      by trust: SignerTrust
    ) -> Bool {
      switch trust {
      case .certificates(let allowed):
        return allowed.contains(certificate)
      case .sha256Fingerprints(let allowed):
        return allowed.contains(Data(SHA256.hash(data: certificate)))
      }
    }
  }

#endif
