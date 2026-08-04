import Foundation
import Security

@testable import ReFineID

/// Generated, hermetic ETSI trusted-list signatures for direct tests.
internal enum TrustedListXmlSignatureFixtures {
  /// XML signature profiles accepted by the production boundary.
  internal enum Profile: CaseIterable {
    /// ECDSA with SHA-256 and XMLDSig's raw r||s value.
    case ecdsaSha256

    /// ECDSA with SHA-512 and XMLDSig's raw r||s value.
    case ecdsaSha512

    /// RSA-PSS with SHA-256 through the fixed-profile URI.
    case rsaPssSha256

    /// RSA-PSS with explicit SHA-256 parameters.
    case rsaPssSha256Parameterized

    /// RSA PKCS#1 v1.5 with SHA-256.
    case rsaSha256

    /// RSA PKCS#1 v1.5 with SHA-512.
    case rsaSha512

    /// Explicit parameters for the generic RSA-PSS method URI.
    private static var parameterizedPssMethod: String {
      let xml = TrustedListXmlSignature.Xml.self
      return """
        <ds:SignatureMethod Algorithm="\(xml.rsaPssWithParameters)">
          <pss:RSAPSSParams xmlns:pss="http://www.w3.org/2007/05/xmldsig-more#">
            <ds:DigestMethod Algorithm="\(xml.digestSha256)"/>
            <pss:MaskGenerationFunction Algorithm="http://www.w3.org/2009/xmlenc11#mgf1sha256"/>
            <pss:SaltLength>32</pss:SaltLength>
            <pss:TrailerField>1</pss:TrailerField>
          </pss:RSAPSSParams>
        </ds:SignatureMethod>
        """
    }

    /// Digest applied to both signed references.
    internal var digest: TrustedListXmlSignature.DigestAlgorithm {
      switch self {
      case .ecdsaSha512, .rsaSha512:
        return .sha512
      case .ecdsaSha256, .rsaPssSha256, .rsaPssSha256Parameterized, .rsaSha256:
        return .sha256
      }
    }

    /// Digest algorithm URI placed in each Reference.
    internal var digestUri: String {
      switch self.digest {
      case .sha256:
        return TrustedListXmlSignature.Xml.digestSha256
      case .sha512:
        return TrustedListXmlSignature.Xml.digestSha512
      }
    }

    /// The generated signer's key family.
    internal var keyKind: KeyKind {
      switch self {
      case .ecdsaSha256:
        return .ecdsaP256
      case .ecdsaSha512:
        return .ecdsaP521
      case .rsaPssSha256, .rsaPssSha256Parameterized, .rsaSha256, .rsaSha512:
        return .rsa
      }
    }

    /// Security operation used to create SignatureValue.
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

    /// Complete SignatureMethod markup for the profile.
    internal var signatureMethod: String {
      let xml = TrustedListXmlSignature.Xml.self
      switch self {
      case .ecdsaSha256:
        return "<ds:SignatureMethod Algorithm=\"\(xml.ecdsaSha256)\"/>"
      case .ecdsaSha512:
        return "<ds:SignatureMethod Algorithm=\"\(xml.ecdsaSha512)\"/>"
      case .rsaPssSha256:
        return "<ds:SignatureMethod Algorithm=\"\(xml.rsaPssSha256)\"/>"
      case .rsaPssSha256Parameterized:
        return Self.parameterizedPssMethod
      case .rsaSha256:
        return "<ds:SignatureMethod Algorithm=\"\(xml.rsaSha256)\"/>"
      case .rsaSha512:
        return "<ds:SignatureMethod Algorithm=\"\(xml.rsaSha512)\"/>"
      }
    }
  }

  /// Key families needed by current European lists.
  internal enum KeyKind {
    /// P-256 ECDSA.
    case ecdsaP256

    /// P-521 ECDSA.
    case ecdsaP521

    /// 2048-bit RSA.
    case rsa
  }

  /// Controlled X.509 profiles for signer-policy tests.
  internal enum CertificateProfile: Equatable {
    /// No BasicConstraints extension, which denotes an end entity.
    case basicConstraintsAbsent

    /// An explicit CA assertion.
    case certificateAuthority

    /// Estonia's current integer-only end-entity BasicConstraints shape.
    case endEntityPathLength

    /// A certificate that ceased to be valid before the signed issue time.
    case expiredBeforeIssue

    /// No KeyUsage extension, so X.509 imposes no usage restriction.
    case keyUsageAbsent

    /// A present KeyUsage that permits encryption but not signatures.
    case nonSigningKeyUsage

    /// Signing KeyUsage and end-entity BasicConstraints.
    case valid
  }

  /// Controlled SubjectPublicKeyInfo encodings for RSA import tests.
  internal enum SubjectPublicKeyProfile: Equatable {
    /// rsaEncryption with the required NULL parameters.
    case rsaEncryption

    /// id-RSASSA-PSS with absent parameters, as used by Germany's TSL signer.
    case rsaPssAbsentParameters

    /// id-RSASSA-PSS with explicitly empty parameters.
    case rsaPssEmptyParameters

    /// id-RSASSA-PSS with an incompatible INTEGER parameter.
    case rsaPssIntegerParameter

    /// id-RSASSA-PSS with NULL parameters.
    case rsaPssNullParameters

    /// The recognized algorithm but a BIT STRING with nonzero unused bits.
    case rsaPssUnusedBits
  }

  /// Controlled XAdES signer-certificate bindings.
  internal enum XadesBinding: Equatable {
    /// The digest names the exact KeyInfo signer certificate.
    case matching

    /// The signed digest names different bytes.
    case mismatched

    /// SigningCertificateV2 is absent.
    case omitted
  }

  /// One generated private key and its matching X.509 certificate.
  internal struct Signer {
    internal let certificate: Data
    internal let key: SecKey
  }

  /// A signed issue/next-update interval.
  internal struct Window {
    /// A window containing the fixed validation time.
    internal static let current = Self(
      issuedAt: "2026-08-01T00:00:00Z",
      nextUpdate: "2026-09-01T00:00:00Z"
    )

    /// A correctly signed but expired window.
    internal static let stale = Self(
      issuedAt: "2026-06-01T00:00:00Z",
      nextUpdate: "2026-07-01T00:00:00Z"
    )

    internal let issuedAt: String
    internal let nextUpdate: String
  }

  /// Failures constructing test-only cryptographic material.
  internal enum Failure: Error {
    /// Security could not create or export a key.
    case keyCreation

    /// An expected XML node could not be selected.
    case malformedXml

    /// Security could not create a signature.
    case signatureCreation
  }

  /// Placeholder for the whole-document Reference digest.
  internal static let documentDigestMarker = "DOCUMENT_DIGEST_VALUE"

  /// Placeholder for the SignedProperties Reference digest.
  internal static let propertiesDigestMarker = "PROPERTIES_DIGEST_VALUE"

  /// Placeholder for the XML SignatureValue.
  internal static let signatureValueMarker = "SIGNATURE_VALUE"

  /// 2026-08-04T00:00:00Z.
  private static let validationTimeInterval: TimeInterval = 1_785_811_200

  /// Fixed point inside `Window.current`.
  internal static let validationTime = Date(
    timeIntervalSince1970: Self.validationTimeInterval
  )

  /// Creates a complete signed TSL document.
  internal static func signedList(
    profile: Profile,
    signer: Signer,
    window: Window,
    schemeContent: String
  ) throws -> Data {
    try Self.signedList(
      profile: profile,
      signer: signer,
      window: window,
      schemeContent: schemeContent,
      xadesBinding: .matching
    )
  }

  /// Creates a complete signed TSL document with a controlled XAdES binding.
  internal static func signedList(
    profile: Profile,
    signer: Signer,
    window: Window,
    schemeContent: String,
    xadesBinding: XadesBinding
  ) throws -> Data {
    var xml = Self.skeleton(
      profile: profile,
      signer: signer,
      window: window,
      schemeContent: schemeContent,
      xadesBinding: xadesBinding
    )
    xml = try Self.applyingReferenceDigests(to: xml, profile: profile)
    let digested = try TrustedListXmlDocument(Data(xml.utf8))
    let signedInfo = try Self.uniqueNode(
      named: "SignedInfo",
      namespace: TrustedListXmlSignature.Xml.signatureNamespace,
      in: digested
    )
    let canonical = try digested.canonicalized(
      signedInfo,
      excludingSignature: false
    )
    let signature = try Self.sign(
      canonical,
      profile: profile,
      key: signer.key
    )
    xml = xml.replacingOccurrences(
      of: Self.signatureValueMarker,
      with: signature.base64EncodedString()
    )
    return Data(xml.utf8)
  }

  /// Calculates and substitutes both same-document Reference digests.
  private static func applyingReferenceDigests(
    to xml: String,
    profile: Profile
  ) throws -> String {
    let unsigned = try TrustedListXmlDocument(Data(xml.utf8))
    let properties = try Self.uniqueNode(
      named: "SignedProperties",
      namespace: TrustedListXmlSignature.Xml.xadesNamespace,
      in: unsigned
    )
    let documentDigest = profile.digest.digest(
      try unsigned.canonicalized(unsigned.root, excludingSignature: true)
    )
    let propertiesDigest = profile.digest.digest(
      try unsigned.canonicalized(properties, excludingSignature: false)
    )
    var digested = xml.replacingOccurrences(
      of: Self.documentDigestMarker,
      with: documentDigest.base64EncodedString()
    )
    digested = digested.replacingOccurrences(
      of: Self.propertiesDigestMarker,
      with: propertiesDigest.base64EncodedString()
    )
    return digested
  }

  /// Selects exactly one element by local name and namespace.
  private static func uniqueNode(
    named name: String,
    namespace: String,
    in document: TrustedListXmlDocument
  ) throws -> TrustedListXmlDocument.Node {
    let matches = document.descendants(including: document.root).filter {
      node in
      document.matches(node, name: name, namespace: namespace)
    }
    guard matches.count == 1, let node = matches.first else {
      throw Failure.malformedXml
    }
    return node
  }
}
