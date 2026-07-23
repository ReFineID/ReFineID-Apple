import CardCore
import CryptoKit
import CryptoTokenKit
import Foundation
import Security

/// Maps a CryptoTokenKit `TKTokenKeyAlgorithm` to the card algorithm and
/// digest for a signature.
///
/// This is the load-bearing, live-only-validatable seam: system TLS
/// hands a `TKTokenKeyAlgorithm` (which cannot be unit-constructed), and
/// we must both advertise the shapes the card can sign and produce the
/// right digest for each. ECDSA is hash-agnostic, so the card signs any
/// digest under the matching algorithm reference; for the "message"
/// forms we hash the input ourselves, for the "digest" forms the input
/// already is the digest. Everything here is logged so the live trace
/// shows exactly what was asked and what matched.
internal enum SigningAlgorithmResolver {
  /// One advertised shape: the platform algorithm, the card hash, and
  /// whether the input must be hashed first.
  private struct Shape {
    let secKeyAlgorithm: SecKeyAlgorithm
    let hash: SigningHash
    let hashesMessage: Bool
  }

  /// The ECDSA shapes advertised for the P-384 auth key.
  ///
  /// SHA-224 and SHA-1 message forms are omitted: CryptoKit does not
  /// provide those hashes and TLS uses the digest forms in practice.
  private static let ecdsaShapes: [Shape] = [
    Shape(secKeyAlgorithm: .ecdsaSignatureDigestX962SHA256, hash: .sha256, hashesMessage: false),
    Shape(secKeyAlgorithm: .ecdsaSignatureMessageX962SHA256, hash: .sha256, hashesMessage: true),
    Shape(secKeyAlgorithm: .ecdsaSignatureDigestX962SHA384, hash: .sha384, hashesMessage: false),
    Shape(secKeyAlgorithm: .ecdsaSignatureMessageX962SHA384, hash: .sha384, hashesMessage: true),
    Shape(secKeyAlgorithm: .ecdsaSignatureDigestX962SHA512, hash: .sha512, hashesMessage: false),
    Shape(secKeyAlgorithm: .ecdsaSignatureMessageX962SHA512, hash: .sha512, hashesMessage: true),
    Shape(secKeyAlgorithm: .ecdsaSignatureDigestX962SHA224, hash: .sha224, hashesMessage: false),
    Shape(secKeyAlgorithm: .ecdsaSignatureDigestRFC4754SHA384, hash: .sha384, hashesMessage: false),
  ]

  /// Every ECDSA SecKey algorithm a TLS stack might request, named for
  /// the log so a live trace shows exactly what Safari asked for - the
  /// only reliable way to see why `supports` answered NO.
  private static let knownAlgorithms: [(String, SecKeyAlgorithm)] = [
    ("digX962SHA256", .ecdsaSignatureDigestX962SHA256),
    ("msgX962SHA256", .ecdsaSignatureMessageX962SHA256),
    ("digX962SHA384", .ecdsaSignatureDigestX962SHA384),
    ("msgX962SHA384", .ecdsaSignatureMessageX962SHA384),
    ("digX962SHA512", .ecdsaSignatureDigestX962SHA512),
    ("msgX962SHA512", .ecdsaSignatureMessageX962SHA512),
    ("digX962SHA224", .ecdsaSignatureDigestX962SHA224),
    ("msgX962SHA224", .ecdsaSignatureMessageX962SHA224),
    ("digRFC4754SHA256", .ecdsaSignatureDigestRFC4754SHA256),
    ("digRFC4754SHA384", .ecdsaSignatureDigestRFC4754SHA384),
    ("digRFC4754SHA512", .ecdsaSignatureDigestRFC4754SHA512),
  ]

  /// True when the token should advertise `algorithm` for signing.
  internal static func advertises(
    _ algorithm: TKTokenKeyAlgorithm,
    profile: CardKeyProfile
  ) -> Bool {
    shapes(for: profile).contains { algorithm.isAlgorithm($0.secKeyAlgorithm) }
  }

  /// Names every known ECDSA algorithm the request `isAlgorithm` of.
  ///
  /// For the live trace. An empty match falls back to the opaque
  /// description so an unexpected request is still visible.
  internal static func describe(_ algorithm: TKTokenKeyAlgorithm) -> String {
    let matches = knownAlgorithms.filter { algorithm.isAlgorithm($0.1) }.map(\.0)
    return matches.isEmpty ? "unrecognized(\(algorithm))" : matches.joined(separator: "+")
  }

  /// Whether the token can sign at all with this profile.
  ///
  /// A profile with no advertised shapes must not publish a sign-capable
  /// identity: `supports` would answer NO to every algorithm, so Safari
  /// offers the certificate but the signature is never reached - no PIN
  /// prompt, and the handshake fails. The token refuses to publish such a
  /// profile rather than promise a login it cannot complete.
  internal static func supportsSigning(_ profile: CardKeyProfile) -> Bool {
    !shapes(for: profile).isEmpty
  }

  /// Resolves the request to a card algorithm and digest, or nil when no
  /// advertised shape matches or the card cannot report a signature
  /// length for the profile.
  internal static func resolve(
    _ algorithm: TKTokenKeyAlgorithm,
    input: Data,
    profile: CardKeyProfile
  ) -> SignRequest? {
    guard
      let shape = shapes(for: profile)
        .first(where: { algorithm.isAlgorithm($0.secKeyAlgorithm) }),
      let signatureLength = ExpectedResponseLength(count: profile.rawSignatureLength)
    else {
      return nil
    }
    let digest = shape.hashesMessage ? Self.hash(input, with: shape.hash) : input
    return SignRequest(
      algorithm: SigningAlgorithm(hash: shape.hash, scheme: .ecdsa),
      digest: digest,
      expectedSignatureLength: signatureLength,
      verifyAlgorithm: Self.verifyAlgorithm(for: shape.hash)
    )
  }

  /// The digest-form SecKey algorithm for verifying a raw card signature.
  ///
  /// ECDSA signs the loaded digest as-is, so verification against the
  /// leaf always uses the digest form matching the hash.
  private static func verifyAlgorithm(for hash: SigningHash) -> SecKeyAlgorithm {
    switch hash {
    case .sha256:
      .ecdsaSignatureDigestX962SHA256
    case .sha384:
      .ecdsaSignatureDigestX962SHA384
    case .sha512:
      .ecdsaSignatureDigestX962SHA512
    case .sha224:
      .ecdsaSignatureDigestX962SHA224
    }
  }

  private static func shapes(for profile: CardKeyProfile) -> [Shape] {
    switch profile {
    case .ecdsaP384:
      ecdsaShapes
    case .rsa3072:
      []
    }
  }

  private static func hash(_ input: Data, with hash: SigningHash) -> Data {
    switch hash {
    case .sha256:
      Data(SHA256.hash(data: input))
    case .sha384:
      Data(SHA384.hash(data: input))
    case .sha512:
      Data(SHA512.hash(data: input))
    case .sha224:
      // Not reachable: no SHA-224 message shape is advertised.
      input
    }
  }
}
