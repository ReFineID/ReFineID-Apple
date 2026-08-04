#if os(macOS)

  import CardCore
  import Foundation
  import Security

  extension TrustedListXmlSignature {
    /// A supported XML signature method and constrained parameters.
    internal static func signatureAlgorithm(
      in method: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws -> SignatureAlgorithm {
      let children = document.children(of: method)
      let identifier = document.attribute("Algorithm", of: method)
      if identifier == Xml.rsaPssWithParameters {
        try Self.checkSha256PssParameters(children, document: document)
        return .rsaPssSha256Parameterized
      }
      guard children.isEmpty else { throw Failure.unsupportedAlgorithm }
      switch identifier {
      case Xml.ecdsaSha256:
        return .ecdsaSha256
      case Xml.ecdsaSha512:
        return .ecdsaSha512
      case Xml.rsaPssSha256:
        return .rsaPssSha256
      case Xml.rsaSha256:
        return .rsaSha256
      case Xml.rsaSha512:
        return .rsaSha512
      default:
        throw Failure.unsupportedAlgorithm
      }
    }

    /// The generic RSA-PSS URI is accepted only for the SHA-256 profile.
    private static func checkSha256PssParameters(
      _ children: [TrustedListXmlDocument.Node],
      document: TrustedListXmlDocument
    ) throws {
      guard children.count == 1, let parameters = children.first else {
        throw Failure.unsupportedAlgorithm
      }
      let values = document.children(of: parameters)
      guard document.matches(parameters, name: "RSAPSSParams") else {
        throw Failure.unsupportedAlgorithm
      }
      let digest = values.filter { value in
        document.matches(
          value,
          name: "DigestMethod",
          namespace: Xml.signatureNamespace
        )
      }
      let salt = values.filter { value in
        document.matches(value, name: "SaltLength")
      }
      let trailer = values.filter { value in
        document.matches(value, name: "TrailerField")
      }
      let mask = values.filter { value in
        document.matches(value, name: "MaskGenerationFunction")
          || document.matches(value, name: "MGF")
      }
      guard
        values.count == Limits.pssParameterCount,
        digest.count == 1,
        salt.count == 1,
        trailer.count == 1,
        mask.count == 1,
        document.attribute("Algorithm", of: digest[0]) == Xml.digestSha256,
        document.text(of: salt[0]) == String(Limits.pssSaltBytes),
        document.text(of: trailer[0]) == "1",
        Self.isSha256Mask(mask[0], document: document)
      else {
        throw Failure.unsupportedAlgorithm
      }
    }

    /// Whether an RSA-PSS mask-generation parameter is MGF1/SHA-256.
    private static func isSha256Mask(
      _ mask: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) -> Bool {
      let algorithm = document.attribute("Algorithm", of: mask)
      if algorithm == "http://www.w3.org/2009/xmlenc11#mgf1sha256" {
        return document.children(of: mask).isEmpty
      }
      guard
        algorithm == "http://www.w3.org/2007/05/xmldsig-more#MGF1"
      else {
        return false
      }
      let children = document.children(of: mask)
      return children.count == 1
        && document.matches(
          children[0],
          name: "DigestMethod",
          namespace: Xml.signatureNamespace
        )
        && document.attribute("Algorithm", of: children[0])
          == Xml.digestSha256
    }

    /// Converts XMLDSig's raw ECDSA r||s value to Security's DER form.
    internal static func securitySignature(
      _ signature: Data,
      algorithm: SignatureAlgorithm,
      key: SecKey
    ) -> Data? {
      switch algorithm {
      case .ecdsaSha256, .ecdsaSha512:
        break
      case .rsaPssSha256, .rsaPssSha256Parameterized, .rsaSha256, .rsaSha512:
        return signature
      }
      guard
        let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
        let bitCount = attributes[kSecAttrKeySizeInBits] as? Int
      else {
        return nil
      }
      let componentBytes =
        (bitCount + Limits.integerByteRoundingAdjustment)
        / Limits.bitsPerByte
      guard
        signature.count == componentBytes * Limits.signatureComponentCount
      else {
        return nil
      }
      return EcdsaSignature.derFromRawConcatenation(signature)
    }

    /// Imports the embedded public key, with one algorithm-gated workaround.
    ///
    /// Security does not expose Germany's current id-RSASSA-PSS SPKI through
    /// `SecCertificateCopyKey`. Its canonical PKCS#1 key may be imported as an
    /// unrestricted RSA key only for the fixed SHA-256 RSA-PSS XML method.
    internal static func verificationKey(
      certificate: SecCertificate,
      encoded: Data,
      algorithm: SignatureAlgorithm
    ) -> SecKey? {
      if let key = SecCertificateCopyKey(certificate) { return key }
      guard
        algorithm == .rsaPssSha256,
        let publicKey =
          CertificateFacts
          .rsaPssPublicKeyWithAbsentParameters(der: encoded)
      else { return nil }
      let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPublic,
      ]
      var error: Unmanaged<CFError>?
      let key = SecKeyCreateWithData(
        publicKey as CFData,
        attributes as CFDictionary,
        &error
      )
      _ = error?.takeRetainedValue()
      return key
    }

    /// Strict base64 after discarding XML whitespace only.
    internal static func base64(_ encoded: String?) -> Data? {
      guard
        let encoded,
        encoded.unicodeScalars.allSatisfy(\.isASCII)
      else {
        return nil
      }
      let xmlWhitespace: Set<Character> = [" ", "\t", "\n", "\r"]
      let compact = encoded.filter { character in
        !xmlWhitespace.contains(character)
      }
      return Data(base64Encoded: compact)
    }

    /// An ISO 8601 timestamp, with or without fractional seconds.
    internal static func date(_ encoded: String?) -> Date? {
      guard let encoded else { return nil }
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds,
      ]
      if let parsed = fractional.date(from: encoded) { return parsed }
      let whole = ISO8601DateFormatter()
      whole.formatOptions = [.withInternetDateTime]
      return whole.date(from: encoded)
    }
  }

#endif
