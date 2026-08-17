import CryptoKit
import Foundation
import XCTest

final class RappNoiseAndEnvelopeCorpusTests: XCTestCase {
  func testFixedNoiseInputsProloguesAndIdentifiers() throws {
    let corpus = try loadCorpus()
    XCTAssertEqual(corpus.noiseHandshake.count, 2)

    for vector in corpus.noiseHandshake {
      let initiatorPrivate = try Curve25519.KeyAgreement.PrivateKey(
        rawRepresentation: decodeHex(vector.testOnlyInitiatorStaticPrivateHex)
      )
      let responderPrivate = try Curve25519.KeyAgreement.PrivateKey(
        rawRepresentation: decodeHex(vector.testOnlyResponderStaticPrivateHex)
      )

      XCTAssertEqual(
        encodeHex(initiatorPrivate.publicKey.rawRepresentation),
        vector.initiatorStaticPublicHex,
        vector.name
      )
      XCTAssertEqual(
        encodeHex(responderPrivate.publicKey.rawRepresentation),
        vector.responderStaticPublicHex,
        vector.name
      )

      let expectedPrologue: Data
      let expectedMessageLengths: [Int]
      switch vector.name {
      case "pairing-xxpsk3-fixed-transcript":
        expectedPrologue = encodeArray([
          encodeText("RAPP-pairing-v1"),
          encodeArray([encodeUnsigned(0), encodeUnsigned(1)]),
          encodeText(vector.suite),
          encodeBytes(try XCTUnwrap(vector.offerHashHex).decodedHex()),
          encodeText(vector.transportProfile),
        ])
        expectedMessageLengths = [48, 96, 64]
        XCTAssertEqual(try XCTUnwrap(vector.testOnlyPairingSecretHex).decodedHex().count, 32)
      case "session-kk-fixed-transcript":
        expectedPrologue = encodeArray([
          encodeText("RAPP-session-v1"),
          encodeArray([encodeUnsigned(0), encodeUnsigned(1)]),
          encodeText(vector.suite),
          encodeBytes(vector.pairIDHex.decodedHex()),
          encodeBytes(try XCTUnwrap(vector.grantsHashHex).decodedHex()),
          encodeText(vector.transportProfile),
        ])
        expectedMessageLengths = [48, 48]
      default:
        XCTFail("Unknown Noise vector: \(vector.name)")
        continue
      }

      XCTAssertEqual(encodeHex(expectedPrologue), vector.prologueHex, vector.name)
      XCTAssertEqual(
        vector.messagesHex.map { $0.decodedHex().count },
        expectedMessageLengths,
        vector.name
      )
      XCTAssertTrue(vector.messagesHex.allSatisfy { !$0.decodedHex().isEmpty }, vector.name)

      let handshakeHash = vector.handshakeHashHex.decodedHex()
      XCTAssertEqual(handshakeHash.count, 32, vector.name)
      XCTAssertEqual(
        deriveIdentifier(domain: "RAPP-session-id-v1", handshakeHash: handshakeHash),
        vector.sessionIDHex,
        vector.name
      )
      if vector.name.hasPrefix("pairing-") {
        XCTAssertEqual(
          deriveIdentifier(domain: "RAPP-pair-id-v1", handshakeHash: handshakeHash),
          vector.pairIDHex,
          vector.name
        )
      }

      XCTAssertEqual(vector.testOnlyInitiatorEphemeralPrivateHex.decodedHex().count, 32)
      XCTAssertEqual(vector.testOnlyResponderEphemeralPrivateHex.decodedHex().count, 32)
    }
  }

  func testMalformedEnvelopesMatchIndependentSwiftDecoder() throws {
    let corpus = try loadCorpus()
    XCTAssertEqual(corpus.rejectedEnvelope.count, 12)

    for vector in corpus.rejectedEnvelope {
      let encoded = vector.canonicalCBORHex.decodedHex()
      var decoder = BoundedCBORDecoder(data: encoded)
      let value = try decoder.decode()
      XCTAssertTrue(decoder.isAtEnd, "Trailing bytes in \(vector.name)")
      XCTAssertEqual(
        validateEnvelope(value, supportedCritical: Set(vector.supportedCritical)),
        vector.error,
        vector.name
      )
    }
  }

  private func loadCorpus() throws -> Corpus {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = repositoryRoot
      .appendingPathComponent("Documentation")
      .appendingPathComponent("rapp-conformance")
      .appendingPathComponent("rapp-v26.8.16.85.json")
    return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
  }

  private func deriveIdentifier(domain: String, handshakeHash: Data) -> String {
    var input = Data(domain.utf8)
    input.append(handshakeHash)
    return encodeHex(Data(SHA256.hash(data: input)).prefix(16))
  }
}

private struct Corpus: Decodable {
  let noiseHandshake: [NoiseVector]
  let rejectedEnvelope: [RejectedEnvelopeVector]

  enum CodingKeys: String, CodingKey {
    case noiseHandshake = "noise_handshake"
    case rejectedEnvelope = "rejected_envelope"
  }
}

private struct NoiseVector: Decodable {
  let name: String
  let suite: String
  let transportProfile: String
  let handshakeHashHex: String
  let initiatorStaticPublicHex: String
  let responderStaticPublicHex: String
  let messagesHex: [String]
  let prologueHex: String
  let pairIDHex: String
  let sessionIDHex: String
  let offerHashHex: String?
  let grantsHashHex: String?
  let testOnlyInitiatorEphemeralPrivateHex: String
  let testOnlyInitiatorStaticPrivateHex: String
  let testOnlyPairingSecretHex: String?
  let testOnlyResponderEphemeralPrivateHex: String
  let testOnlyResponderStaticPrivateHex: String

  enum CodingKeys: String, CodingKey {
    case name, suite
    case transportProfile = "transport_profile"
    case handshakeHashHex = "handshake_hash_hex"
    case initiatorStaticPublicHex = "initiator_static_public_hex"
    case responderStaticPublicHex = "responder_static_public_hex"
    case messagesHex = "messages_hex"
    case prologueHex = "prologue_hex"
    case pairIDHex = "pair_id_hex"
    case sessionIDHex = "session_id_hex"
    case offerHashHex = "offer_hash_hex"
    case grantsHashHex = "grants_hash_hex"
    case testOnlyInitiatorEphemeralPrivateHex = "test_only_initiator_ephemeral_private_hex"
    case testOnlyInitiatorStaticPrivateHex = "test_only_initiator_static_private_hex"
    case testOnlyPairingSecretHex = "test_only_pairing_secret_hex"
    case testOnlyResponderEphemeralPrivateHex = "test_only_responder_ephemeral_private_hex"
    case testOnlyResponderStaticPrivateHex = "test_only_responder_static_private_hex"
  }
}

private struct RejectedEnvelopeVector: Decodable {
  let name: String
  let canonicalCBORHex: String
  let error: String
  let supportedCritical: [String]

  enum CodingKeys: String, CodingKey {
    case name, error
    case canonicalCBORHex = "canonical_cbor_hex"
    case supportedCritical = "supported_critical"
  }
}

private enum CBORValue: Equatable {
  case unsigned(UInt64)
  case bytes(Data)
  case text(String)
  case array([CBORValue])
  case map([String: CBORValue])
}

private enum CBORDecodeError: Error {
  case truncated
  case unsupported
  case invalidUTF8
  case duplicateKey
  case limitExceeded
}

private struct BoundedCBORDecoder {
  private let bytes: [UInt8]
  private var offset = 0

  init(data: Data) {
    bytes = Array(data)
  }

  var isAtEnd: Bool { offset == bytes.count }

  mutating func decode(depth: Int = 0) throws -> CBORValue {
    guard depth < 16 else { throw CBORDecodeError.limitExceeded }
    let initial = try readByte()
    let major = initial >> 5
    let count = try readLength(initial & 0x1f)

    switch major {
    case 0:
      return .unsigned(count)
    case 2:
      return .bytes(try readData(count))
    case 3:
      let data = try readData(count)
      guard let value = String(data: data, encoding: .utf8) else {
        throw CBORDecodeError.invalidUTF8
      }
      return .text(value)
    case 4:
      guard count <= 128 else { throw CBORDecodeError.limitExceeded }
      return .array(try (0..<Int(count)).map { _ in try decode(depth: depth + 1) })
    case 5:
      guard count <= 128 else { throw CBORDecodeError.limitExceeded }
      var result: [String: CBORValue] = [:]
      for _ in 0..<Int(count) {
        guard case let .text(key) = try decode(depth: depth + 1) else {
          throw CBORDecodeError.unsupported
        }
        guard result[key] == nil else { throw CBORDecodeError.duplicateKey }
        result[key] = try decode(depth: depth + 1)
      }
      return .map(result)
    default:
      throw CBORDecodeError.unsupported
    }
  }

  private mutating func readLength(_ additional: UInt8) throws -> UInt64 {
    switch additional {
    case 0...23:
      return UInt64(additional)
    case 24:
      return UInt64(try readByte())
    case 25:
      return try readBigEndian(byteCount: 2)
    case 26:
      return try readBigEndian(byteCount: 4)
    case 27:
      return try readBigEndian(byteCount: 8)
    default:
      throw CBORDecodeError.unsupported
    }
  }

  private mutating func readBigEndian(byteCount: Int) throws -> UInt64 {
    var value: UInt64 = 0
    for _ in 0..<byteCount {
      value = (value << 8) | UInt64(try readByte())
    }
    return value
  }

  private mutating func readByte() throws -> UInt8 {
    guard offset < bytes.count else { throw CBORDecodeError.truncated }
    defer { offset += 1 }
    return bytes[offset]
  }

  private mutating func readData(_ count: UInt64) throws -> Data {
    guard count <= 16_384, count <= UInt64(bytes.count - offset) else {
      throw CBORDecodeError.limitExceeded
    }
    let end = offset + Int(count)
    defer { offset = end }
    return Data(bytes[offset..<end])
  }
}

private func validateEnvelope(
  _ value: CBORValue,
  supportedCritical: Set<String>
) -> String? {
  guard case let .map(envelope) = value else { return "WrongType { field: \"envelope\" }" }
  let allowed = Set(["version", "session_id", "sequence", "type", "body", "critical", "extensions"])
  guard Set(envelope.keys).isSubset(of: allowed) else { return "UnknownField" }

  guard let version = envelope["version"] else { return "MissingField { field: \"version\" }" }
  guard case let .array(parts) = version,
        parts.count == 2,
        case let .unsigned(major) = parts[0],
        case let .unsigned(minor) = parts[1]
  else { return "WrongType { field: \"version\" }" }
  guard major == 0, minor == 1 else { return "UnsupportedVersion" }

  guard case let .bytes(sessionID)? = envelope["session_id"] else {
    return "WrongType { field: \"session_id\" }"
  }
  guard sessionID.count == 16 else {
    return "WrongLength { field: \"session_id\", expected: 16, got: \(sessionID.count) }"
  }
  guard case .unsigned? = envelope["sequence"] else {
    return "WrongType { field: \"sequence\" }"
  }
  guard case let .text(type)? = envelope["type"] else {
    return "WrongType { field: \"type\" }"
  }
  guard type == "liveness.ping" else { return "UnknownMessageType" }
  guard case let .map(body)? = envelope["body"] else {
    return "WrongType { field: \"body\" }"
  }
  guard case let .bytes(challenge)? = body["challenge"], challenge.count == 32,
        case .unsigned? = body["last_received_sequence"]
  else { return "WrongType { field: \"body\" }" }

  var critical: [String] = []
  if let criticalValue = envelope["critical"] {
    guard case let .array(entries) = criticalValue else {
      return "WrongType { field: \"critical\" }"
    }
    for entry in entries {
      guard case let .text(name) = entry else {
        return "WrongType { field: \"critical\" }"
      }
      critical.append(name)
    }
  }

  var extensions: [String: CBORValue] = [:]
  if let extensionsValue = envelope["extensions"] {
    guard case let .map(entries) = extensionsValue else {
      return "WrongType { field: \"extensions\" }"
    }
    extensions = entries
  }
  guard critical.allSatisfy({ extensions[$0] != nil }) else {
    return "CriticalExtensionMissing"
  }
  guard critical.allSatisfy(supportedCritical.contains) else {
    return "UnsupportedCriticalExtension"
  }
  return nil
}

private func encodeUnsigned(_ value: UInt64) -> Data {
  encodeMajor(0, value: value)
}

private func encodeBytes(_ value: Data) -> Data {
  var result = encodeMajor(2, value: UInt64(value.count))
  result.append(value)
  return result
}

private func encodeText(_ value: String) -> Data {
  let utf8 = Data(value.utf8)
  var result = encodeMajor(3, value: UInt64(utf8.count))
  result.append(utf8)
  return result
}

private func encodeArray(_ values: [Data]) -> Data {
  var result = encodeMajor(4, value: UInt64(values.count))
  values.forEach { result.append($0) }
  return result
}

private func encodeMajor(_ major: UInt8, value: UInt64) -> Data {
  let prefix = major << 5
  switch value {
  case 0...23:
    return Data([prefix | UInt8(value)])
  case 24...0xff:
    return Data([prefix | 24, UInt8(value)])
  case 0x100...0xffff:
    return Data([prefix | 25, UInt8(value >> 8), UInt8(value)])
  case 0x1_0000...0xffff_ffff:
    return Data([prefix | 26] + (0..<4).reversed().map { UInt8(value >> UInt64($0 * 8)) })
  default:
    return Data([prefix | 27] + (0..<8).reversed().map { UInt8(value >> UInt64($0 * 8)) })
  }
}

private func decodeHex(_ value: String) throws -> Data {
  value.decodedHex()
}

private func encodeHex(_ value: Data) -> String {
  value.map { String(format: "%02x", $0) }.joined()
}

private extension String {
  func decodedHex() -> Data {
    precondition(count.isMultiple(of: 2), "Odd hex length")
    var result = Data()
    result.reserveCapacity(count / 2)
    var index = startIndex
    while index < endIndex {
      let next = self.index(index, offsetBy: 2)
      guard let byte = UInt8(self[index..<next], radix: 16) else {
        preconditionFailure("Invalid hex")
      }
      result.append(byte)
      index = next
    }
    return result
  }
}
