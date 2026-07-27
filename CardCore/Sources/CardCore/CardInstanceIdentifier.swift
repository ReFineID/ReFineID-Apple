import CryptoKit
import Foundation

/// The identifier one card's token is published under.
///
/// One type and one contents version serve both transports, because they
/// are one decision. What differs is only what there is to digest at the
/// moment the identifier has to exist:
///
/// - A contact card is read before its token is minted, so the leaf
///   certificate is in hand and names the card exactly.
/// - A contactless card answers nothing until PACE has run, and the
///   driver must name it before it can even look up the prime that would
///   let PACE run. The answer to reset is the only thing the system can
///   see that early. It differs between a card's contact and contactless
///   interfaces, so a contact insertion can never collide with a primed
///   contactless identity.
///
/// The identifier carries a contents version because `ctkd` caches a
/// token's published keychain contents by instance ID and restores them
/// on the next insert WITHOUT re-running `createToken`. A build that
/// changes the published item set -- adding the issuer certificate,
/// changing a key's advertised shape -- therefore keeps serving the old
/// contents until the identifier changes too. Bumping
/// ``contentsVersion`` is what forces `ctkd` to rebuild; without the bump
/// the stale cache silently wins and the new code never runs. The two
/// transports share the one constant, so the bump cannot be made for one
/// and forgotten for the other.
///
/// Provenance: `Token.primedInstanceID(for:)` and `Token.contentsVersion`
/// in the donor `platform/apple/RefineIDTokenExtension/Token.swift`,
/// where the digest and the version suffix were assembled at each call
/// site.
public struct CardInstanceIdentifier: Equatable, Hashable, Sendable {
  /// Version of the item set a token publishes under this identifier.
  ///
  /// Bump this whenever the published keychain contents or the side
  /// effects of creating a token change, so a card already known to
  /// `ctkd` gets a fresh identifier instead of its cached copy of the
  /// old one. v2 = the signing key carries the PIN1 signData constraint.
  public static let contentsVersion: String = "2"

  /// Separates the digest from the contents version.
  private static let versionSeparator: String = "."

  /// Formats one digest byte as two lowercase hex digits.
  private static let byteHexFormat: String = "%02x"

  /// Hex characters of the certificate digest kept in the identifier --
  /// enough to name the card without an oversized identifier.
  ///
  /// The answer-to-reset derivation keeps the whole digest instead. An
  /// ATR is shared across a production batch far more readily than a
  /// certificate is, so that one is given no truncation to collide in.
  private static let certificateDigestLength: Int = 16

  /// The identifier string: digest first, contents version last.
  public let value: String

  /// Derives the identifier from a slot's answer to reset, for a card
  /// that has to be named before it can be read.
  ///
  /// Refuses an empty ATR. A slot that reports no ATR has not identified
  /// a card, and folding that absence into the digest would give every
  /// such slot the same identifier -- one card's primed identity would
  /// then be served for a different card.
  public init?(answerToReset atr: Data) {
    guard !atr.isEmpty else { return nil }
    self.init(digestOf: atr, keeping: nil)
  }

  /// Derives the identifier from the card's authentication certificate,
  /// for a card that was read before its token was minted.
  ///
  /// Refuses empty bytes for the same reason as an empty ATR: an
  /// identifier that names no particular card names all of them.
  public init?(authenticationCertificate der: Data) {
    guard !der.isEmpty else { return nil }
    self.init(digestOf: der, keeping: Self.certificateDigestLength)
  }

  /// Assembles the identifier from a digest of `material`, keeping
  /// `characters` hex digits of it, or all of them when nil.
  private init(digestOf material: Data, keeping characters: Int?) {
    let digest = SHA256.hash(data: material)
      .map { String(format: Self.byteHexFormat, $0) }
      .joined()
    let kept = characters.map { String(digest.prefix($0)) } ?? digest
    self.value = kept + Self.versionSeparator + Self.contentsVersion
  }
}
