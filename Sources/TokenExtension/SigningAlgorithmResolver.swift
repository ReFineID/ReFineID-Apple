import CardCore
import CryptoKit
import CryptoTokenKit
import Foundation
import Security

/// Resolves CryptoTokenKit sign requests to the exact on-card operation.
internal enum SigningAlgorithmResolver {
  /// One advertised request shape.
  private struct Shape {
    let secKeyAlgorithm: SecKeyAlgorithm
    let hash: SigningHash
    let scheme: SigningScheme
    let hashesMessage: Bool
  }

  /// ECDSA shapes supported by the P-384 authentication key.
  private static let ecdsaShapes: [Shape] = [
    Shape(
      secKeyAlgorithm: .ecdsaSignatureDigestX962SHA256,
      hash: .sha256,
      scheme: .ecdsa,
      hashesMessage: false),
    Shape(
      secKeyAlgorithm: .ecdsaSignatureMessageX962SHA256,
      hash: .sha256,
      scheme: .ecdsa,
      hashesMessage: true),
    Shape(
      secKeyAlgorithm: .ecdsaSignatureDigestX962SHA384,
      hash: .sha384,
      scheme: .ecdsa,
      hashesMessage: false),
    Shape(
      secKeyAlgorithm: .ecdsaSignatureMessageX962SHA384,
      hash: .sha384,
      scheme: .ecdsa,
      hashesMessage: true),
    Shape(
      secKeyAlgorithm: .ecdsaSignatureDigestX962SHA512,
      hash: .sha512,
      scheme: .ecdsa,
      hashesMessage: false),
    Shape(
      secKeyAlgorithm: .ecdsaSignatureMessageX962SHA512,
      hash: .sha512,
      scheme: .ecdsa,
      hashesMessage: true),
    Shape(
      secKeyAlgorithm: .ecdsaSignatureDigestX962SHA224,
      hash: .sha224,
      scheme: .ecdsa,
      hashesMessage: false),
    Shape(
      secKeyAlgorithm: .ecdsaSignatureDigestRFC4754SHA384,
      hash: .sha384,
      scheme: .ecdsa,
      hashesMessage: false),
  ]

  /// Old-card RSA-3072 client-auth shapes.
  ///
  /// TLS 1.3 chooses PSS. PKCS#1 v1.5 remains for TLS 1.2 relying
  /// parties. Message variants are hashed exactly once here; digest
  /// variants must already be exactly one SHA-256 digest.
  private static let rsaShapes: [Shape] = [
    Shape(
      secKeyAlgorithm: .rsaSignatureDigestPSSSHA256,
      hash: .sha256,
      scheme: .rsaPss,
      hashesMessage: false),
    Shape(
      secKeyAlgorithm: .rsaSignatureMessagePSSSHA256,
      hash: .sha256,
      scheme: .rsaPss,
      hashesMessage: true),
    Shape(
      secKeyAlgorithm: .rsaSignatureDigestPKCS1v15SHA256,
      hash: .sha256,
      scheme: .rsaPkcs1,
      hashesMessage: false),
    Shape(
      secKeyAlgorithm: .rsaSignatureMessagePKCS1v15SHA256,
      hash: .sha256,
      scheme: .rsaPkcs1,
      hashesMessage: true),
  ]

  /// Known candidates used only to make the live CTK request legible.
  private static let knownAlgorithms: [(String, SecKeyAlgorithm)] = [
    ("ecdsaDigestSHA224", .ecdsaSignatureDigestX962SHA224),
    ("ecdsaDigestSHA256", .ecdsaSignatureDigestX962SHA256),
    ("ecdsaMessageSHA256", .ecdsaSignatureMessageX962SHA256),
    ("ecdsaDigestSHA384", .ecdsaSignatureDigestX962SHA384),
    ("ecdsaMessageSHA384", .ecdsaSignatureMessageX962SHA384),
    ("ecdsaDigestSHA512", .ecdsaSignatureDigestX962SHA512),
    ("ecdsaMessageSHA512", .ecdsaSignatureMessageX962SHA512),
    ("ecdsaDigestRFC4754SHA384", .ecdsaSignatureDigestRFC4754SHA384),
    ("rsaRaw", .rsaSignatureRaw),
    ("rsaDigestPSSSHA256", .rsaSignatureDigestPSSSHA256),
    ("rsaMessagePSSSHA256", .rsaSignatureMessagePSSSHA256),
    ("rsaDigestPKCS1SHA256", .rsaSignatureDigestPKCS1v15SHA256),
    ("rsaMessagePKCS1SHA256", .rsaSignatureMessagePKCS1v15SHA256),
  ]

  /// Whether the token should advertise this live CTK algorithm.
  internal static func advertises(
    _ algorithm: TKTokenKeyAlgorithm,
    profile: CardKeyProfile
  ) -> Bool {
    if shapes(for: profile).contains(where: { shape in
      algorithm.isAlgorithm(shape.secKeyAlgorithm)
    }) {
      return true
    }
    return profile == .rsa3072 && isRawRsaPkcs1Request(algorithm)
  }

  /// Names target and associated-chain matches for device traces.
  internal static func describe(_ algorithm: TKTokenKeyAlgorithm) -> String {
    let targets = Self.knownAlgorithms
      .filter { candidate in
        algorithm.isAlgorithm(candidate.1)
      }
      .map(\.0)
    let chain = Self.knownAlgorithms
      .filter { candidate in
        algorithm.supportsAlgorithm(candidate.1)
      }
      .map(\.0)
    let targetLabel = targets.isEmpty ? "none-of-known" : targets.joined(separator: ",")
    let chainLabel = chain.isEmpty ? "none-of-known" : chain.joined(separator: ",")
    return "target=\(targetLabel); chain=\(chainLabel)"
  }

  /// Whether this certificate profile can publish a sign-capable key.
  internal static func supportsSigning(_ profile: CardKeyProfile) -> Bool {
    !shapes(for: profile).isEmpty
  }

  /// Resolves one live CTK request, including Apple's raw-RSA adapter.
  internal static func resolve(
    _ algorithm: TKTokenKeyAlgorithm,
    input: Data,
    profile: CardKeyProfile
  ) -> SignRequest? {
    if let shape = shapes(for: profile).first(where: { shape in
      algorithm.isAlgorithm(shape.secKeyAlgorithm)
    }) {
      let digest: Data
      if shape.hashesMessage {
        digest = hash(input, with: shape.hash)
      } else {
        guard input.count == shape.hash.digestByteCount else { return nil }
        digest = input
      }
      return request(shape: shape, digest: digest, profile: profile)
    }

    // Security.framework can apply EMSA-PKCS1-v1_5 itself and ask a
    // smart-card token for the raw private-key primitive. Validate and
    // invert only the exact RSA-3072/SHA-256 block our card can reproduce.
    guard
      profile == .rsa3072,
      isRawRsaPkcs1Request(algorithm),
      let encoded = Rsa3072Pkcs1Sha256EncodedMessage(encoded: input)
    else {
      return nil
    }
    let rawShape = Shape(
      secKeyAlgorithm: .rsaSignatureRaw,
      hash: .sha256,
      scheme: .rsaPkcs1,
      hashesMessage: false)
    return request(shape: rawShape, digest: encoded.digest, profile: profile)
  }

  /// Constructs the shared request after input normalization.
  private static func request(
    shape: Shape,
    digest: Data,
    profile: CardKeyProfile
  ) -> SignRequest? {
    SignRequest.resolve(
      profile: profile,
      algorithm: SigningAlgorithm(hash: shape.hash, scheme: shape.scheme),
      digest: digest
    )
  }

  /// Apple's raw target plus a PKCS#1/SHA-256 associated chain.
  private static func isRawRsaPkcs1Request(_ algorithm: TKTokenKeyAlgorithm) -> Bool {
    algorithm.isAlgorithm(.rsaSignatureRaw)
      && algorithm.supportsAlgorithm(.rsaSignatureDigestPKCS1v15SHA256)
  }

  private static func shapes(for profile: CardKeyProfile) -> [Shape] {
    switch profile {
    case .ecdsaP384:
      Self.ecdsaShapes
    case .rsa3072:
      Self.rsaShapes
    }
  }

  private static func hash(_ input: Data, with hash: SigningHash) -> Data {
    switch hash {
    case .sha224:
      // No SHA-224 message form is advertised.
      input
    case .sha256:
      Data(SHA256.hash(data: input))
    case .sha384:
      Data(SHA384.hash(data: input))
    case .sha512:
      Data(SHA512.hash(data: input))
    }
  }
}
