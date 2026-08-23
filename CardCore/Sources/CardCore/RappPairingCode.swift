// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import CryptoKit
  import Foundation
  import RappEngine
  import Security

  /// Generates, formats, and validates 8-character alphanumeric pairing codes
  /// for simple, secure out-of-band peer pairing without QR codes.
  public enum RappPairingCode {

    // MARK: Static Properties

    /// The standard character length of an alphanumeric pairing code.
    public static let codeLength = 8

    private static let hyphenIndex = 4
    private static let sha256ByteCount = 32
    private static let defaultOfferIdByteCount = 16
    private static let defaultPairingSecretByteCount = 32
    @usableFromInline internal static let defaultLifetimeMilliseconds: UInt64 = 180_000
    @usableFromInline internal static let emptyCborMap = Data([0b1010_0000])

    /// Uppercase alphanumeric alphabet [A-Z0-9].
    private static let alphabet: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    // MARK: Static Functions

    /// Generates a fresh cryptographically secure random 8-character pairing code.
    public static func generate() -> String {
      var bytes = [UInt8](repeating: 0, count: codeLength)
      _ = SecRandomCopyBytes(kSecRandomDefault, codeLength, &bytes)
      return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// Normalizes raw input: removes whitespace and non-alphanumeric characters, uppercases.
    public static func normalize(_ input: String) -> String {
      let filtered = input.uppercased().filter { char in
        ("A"..."Z").contains(char) || ("0"..."9").contains(char)
      }
      return String(filtered.prefix(codeLength))
    }

    /// Formats the code for clear display.
    ///
    /// Splits an 8-character code with a hyphen (for example, "ABCD-1234").
    public static func format(_ code: String) -> String {
      let normalized = normalize(code)
      guard normalized.count > hyphenIndex else { return normalized }
      let index = normalized.index(normalized.startIndex, offsetBy: hyphenIndex)
      return String(normalized[..<index]) + "-" + String(normalized[index...])
    }

    /// Checks if a string is a valid complete 8-character pairing code.
    public static func isValid(_ code: String) -> Bool {
      let filtered = code.uppercased().filter { char in
        ("A"..."Z").contains(char) || ("0"..."9").contains(char)
      }
      return filtered.count == codeLength
    }

    /// Derives the pairing secret deterministically from the 8-character code.
    public static func pairingSecret(for rawCode: String) -> Data {
      let code = normalize(rawCode)
      let count = Int(
        (try? RappPlatformEntropy().pairingSecret().count) ?? defaultPairingSecretByteCount)
      let hash = SHA256.hash(data: Data("refineid-rapp-pairing-secret-v1:\(code)".utf8))
      if count <= sha256ByteCount {
        return Data(hash.prefix(count))
      }
      return Data(hash) + Data(repeating: 0, count: count - sha256ByteCount)
    }

    /// Derives the pairing offer identifier deterministically from the 8-character code.
    public static func offerIdentifier(for rawCode: String) -> Data {
      let code = normalize(rawCode)
      let count = Int((try? RappPlatformEntropy().offerID().count) ?? defaultOfferIdByteCount)
      let hash = SHA256.hash(data: Data("refineid-rapp-offer-id-v1:\(code)".utf8))
      if count <= sha256ByteCount {
        return Data(hash.prefix(count))
      }
      return Data(hash) + Data(repeating: 0, count: count - sha256ByteCount)
    }

    /// Derives the full pairing offer for the given 8-character code and candidate.
    public static func pairingOffer(
      for rawCode: String,
      profiles: [String] = [
        "fi.eid.card-status.v1",
        "fi.eid.authentication.v1",
        "fi.eid.document-signing.v1",
      ],
      candidate: RappTransportCandidate = RappTransportCandidate(
        profile: rappStreamProfileName(),
        candidateId: "stream-1",
        parametersCbor: emptyCborMap
      ),
      lifetimeMilliseconds: UInt64 = defaultLifetimeMilliseconds
    ) throws -> (bridge: RappPairingBridge, uri: String) {
      let code = normalize(rawCode)
      guard isValid(code) else { throw RappBindingError.InvalidInput }
      let secret = pairingSecret(for: code)
      let offerId = offerIdentifier(for: code)
      let clock = RappPlatformClock()
      let startedAt = clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.createRequesterOffer(
        offerId: offerId,
        pairingSecret: secret,
        profiles: profiles,
        transports: [candidate],
        offerTtlMs: lifetimeMilliseconds,
        startedAtMonotonicMs: startedAt
      )
      let uri = try bridge.offerUri(nowMonotonicMs: startedAt)
      return (bridge: bridge, uri: uri)
    }
  }
#endif
