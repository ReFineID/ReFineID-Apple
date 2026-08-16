// Copyright 2026 Petri Koistinen <petri.koistinen@iki.fi>
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CryptoKit
import Foundation
import Testing

@Suite("RAPP independent conformance corpus")
internal struct RappConformanceCorpusTests {
  @Test("Corpus identity and provenance are fixed")
  internal func corpusIdentity() throws {
    let source = try Self.corpusSource()
    let digest = Data(SHA256.hash(data: source))
    #expect(digest.hex == "a8b41c0125b5faf37a1fc18f5deadb5570217a1853071864a3fbaab7f912acc7")

    let corpus = try JSONDecoder().decode(Corpus.self, from: source)
    #expect(corpus.format == "fi.refineid.rapp.conformance-v1")
    #expect(corpus.protocolDocumentVersion == "26.8.16.85")
    #expect(corpus.deterministicCBOR.count == 15)
    #expect(corpus.identifierDerivation.count == 2)
    #expect(corpus.grantsHash.count == 3)
    #expect(corpus.requestHash.count == 1)
    #expect(corpus.rejectedCBOR.count == 8)
  }

  @Test("Swift independently produces every golden deterministic-CBOR value")
  internal func deterministicCBOR() throws {
    for vector in try Self.corpus().deterministicCBOR {
      #expect(try DeterministicCBOR.encode(vector.value) == Data(hex: vector.encodedHex))
    }
  }

  @Test("Swift independently derives pair and session identifiers")
  internal func identifierDerivation() throws {
    for vector in try Self.corpus().identifierDerivation {
      let handshakeHash = try Data(hex: vector.handshakeHashHex)
      let pairInput = Data("RAPP-pair-id-v1".utf8) + handshakeHash
      let sessionInput = Data("RAPP-session-id-v1".utf8) + handshakeHash
      let pairID = Data(SHA256.hash(data: pairInput).prefix(16))
      let sessionID = Data(SHA256.hash(data: sessionInput).prefix(16))
      let expectedPairID = try Data(hex: vector.pairIDHex)
      let expectedSessionID = try Data(hex: vector.sessionIDHex)
      #expect(pairID == expectedPairID)
      #expect(sessionID == expectedSessionID)
    }
  }

  @Test("Swift independently normalizes and commits granted profiles")
  internal func grantsHash() throws {
    for vector in try Self.corpus().grantsHash {
      let profiles = vector.profiles.sorted {
        Data($0.utf8).lexicographicallyPrecedes(Data($1.utf8))
      }
      let preimage = try DeterministicCBOR.encode(
        .array(profiles.map(CorpusValue.text))
      )
      let expectedPreimage = try Data(hex: vector.canonicalCBORHex)
      let expectedHash = try Data(hex: vector.sha256Hex)
      #expect(preimage == expectedPreimage)
      #expect(Data(SHA256.hash(data: preimage)) == expectedHash)
    }
  }

  @Test("Swift independently constructs and commits a request")
  internal func requestHash() throws {
    for vector in try Self.corpus().requestHash {
      let preimageValue = CorpusValue.array([
        .text("RAPP-request-v1"),
        .bytes(try Data(hex: vector.sessionIDHex)),
        .bytes(try Data(hex: vector.operationIDHex)),
        .text(vector.profile),
        .text(vector.action),
        vector.context,
        vector.payload,
      ])
      let preimage = try DeterministicCBOR.encode(preimageValue)
      let expectedPreimage = try Data(hex: vector.preimageCBORHex)
      let expectedHash = try Data(hex: vector.sha256Hex)
      #expect(preimage == expectedPreimage)
      #expect(Data(SHA256.hash(data: preimage)) == expectedHash)
    }
  }

  private static func corpus() throws -> Corpus {
    try JSONDecoder().decode(Corpus.self, from: corpusSource())
  }

  private static func corpusSource() throws -> Data {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try Data(
      contentsOf: repositoryRoot
        .appendingPathComponent("Documentation/rapp-conformance/rapp-v26.8.16.85.json")
    )
  }
}

private struct Corpus: Decodable {
  let format: String
  let protocolDocumentVersion: String
  let deterministicCBOR: [CBORVector]
  let identifierDerivation: [IdentifierVector]
  let grantsHash: [GrantsVector]
  let requestHash: [RequestVector]
  let rejectedCBOR: [RejectedCBORVector]

  private enum CodingKeys: String, CodingKey {
    case format
    case protocolDocumentVersion = "protocol_document_version"
    case deterministicCBOR = "deterministic_cbor"
    case identifierDerivation = "identifier_derivation"
    case grantsHash = "grants_hash"
    case requestHash = "request_hash"
    case rejectedCBOR = "rejected_cbor"
  }
}

private struct CBORVector: Decodable {
  let name: String
  let value: CorpusValue
  let encodedHex: String

  private enum CodingKeys: String, CodingKey {
    case name
    case value
    case encodedHex = "encoded_hex"
  }
}

private struct IdentifierVector: Decodable {
  let name: String
  let handshakeHashHex: String
  let pairIDHex: String
  let sessionIDHex: String

  private enum CodingKeys: String, CodingKey {
    case name
    case handshakeHashHex = "handshake_hash_hex"
    case pairIDHex = "pair_id_hex"
    case sessionIDHex = "session_id_hex"
  }
}

private struct GrantsVector: Decodable {
  let name: String
  let profiles: [String]
  let canonicalCBORHex: String
  let sha256Hex: String

  private enum CodingKeys: String, CodingKey {
    case name
    case profiles
    case canonicalCBORHex = "canonical_cbor_hex"
    case sha256Hex = "sha256_hex"
  }
}

private struct RequestVector: Decodable {
  let name: String
  let sessionIDHex: String
  let operationIDHex: String
  let profile: String
  let action: String
  let context: CorpusValue
  let payload: CorpusValue
  let preimageCBORHex: String
  let sha256Hex: String

  private enum CodingKeys: String, CodingKey {
    case name
    case sessionIDHex = "session_id_hex"
    case operationIDHex = "operation_id_hex"
    case profile
    case action
    case context
    case payload
    case preimageCBORHex = "preimage_cbor_hex"
    case sha256Hex = "sha256_hex"
  }
}

private struct RejectedCBORVector: Decodable {
  let name: String
  let encodedHex: String
  let error: String

  private enum CodingKeys: String, CodingKey {
    case name
    case encodedHex = "encoded_hex"
    case error
  }
}

private indirect enum CorpusValue: Decodable {
  case unsigned(UInt64)
  case negative(Int64)
  case bytes(Data)
  case text(String)
  case array([CorpusValue])
  case map([CorpusMapEntry])
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "unsigned": self = .unsigned(try container.decode(UInt64.self, forKey: .value))
    case "negative": self = .negative(try container.decode(Int64.self, forKey: .value))
    case "bytes": self = .bytes(try Data(hex: container.decode(String.self, forKey: .hex)))
    case "text": self = .text(try container.decode(String.self, forKey: .value))
    case "array": self = .array(try container.decode([CorpusValue].self, forKey: .items))
    case "map": self = .map(try container.decode([CorpusMapEntry].self, forKey: .entries))
    case "bool": self = .bool(try container.decode(Bool.self, forKey: .value))
    case "null": self = .null
    case let kind:
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Unknown corpus value kind \(kind)"
      )
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
    case hex
    case items
    case entries
  }
}

private struct CorpusMapEntry: Decodable {
  let key: String
  let value: CorpusValue
}

private enum DeterministicCBOR {
  static func encode(_ value: CorpusValue) throws -> Data {
    switch value {
    case let .unsigned(number):
      return header(major: 0, value: number)
    case let .negative(number):
      guard number < 0 else { throw CorpusError.invalidNegative }
      return header(major: 1, value: UInt64(-(number + 1)))
    case let .bytes(bytes):
      return header(major: 2, value: UInt64(bytes.count)) + bytes
    case let .text(text):
      let bytes = Data(text.utf8)
      return header(major: 3, value: UInt64(bytes.count)) + bytes
    case let .array(items):
      return try items.reduce(header(major: 4, value: UInt64(items.count))) {
        $0 + (try encode($1))
      }
    case let .map(entries):
      var seen = Set<Data>()
      let encodedEntries = try entries.map { entry -> (Data, Data) in
        let key = try encode(.text(entry.key))
        guard seen.insert(key).inserted else { throw CorpusError.duplicateMapKey }
        return (key, try encode(entry.value))
      }.sorted { left, right in
        left.0.lexicographicallyPrecedes(right.0)
      }
      return encodedEntries.reduce(header(major: 5, value: UInt64(entries.count))) {
        $0 + $1.0 + $1.1
      }
    case let .bool(value):
      return Data([value ? 0xF5 : 0xF4])
    case .null:
      return Data([0xF6])
    }
  }

  private static func header(major: UInt8, value: UInt64) -> Data {
    let prefix = major << 5
    switch value {
    case 0 ... 23:
      return Data([prefix | UInt8(value)])
    case 24 ... UInt64(UInt8.max):
      return Data([prefix | 24, UInt8(value)])
    case 0 ... UInt64(UInt16.max):
      var integer = UInt16(value).bigEndian
      return Data([prefix | 25]) + withUnsafeBytes(of: &integer) { Data($0) }
    case 0 ... UInt64(UInt32.max):
      var integer = UInt32(value).bigEndian
      return Data([prefix | 26]) + withUnsafeBytes(of: &integer) { Data($0) }
    default:
      var integer = value.bigEndian
      return Data([prefix | 27]) + withUnsafeBytes(of: &integer) { Data($0) }
    }
  }
}

private enum CorpusError: Error {
  case invalidHex
  case invalidNegative
  case duplicateMapKey
}

private extension Data {
  init(hex: String) throws {
    let characters = Array(hex.utf8)
    guard characters.count.isMultiple(of: 2) else { throw CorpusError.invalidHex }
    self.init()
    reserveCapacity(characters.count / 2)
    for index in stride(from: 0, to: characters.count, by: 2) {
      guard
        let high = Self.hexNibble(characters[index]),
        let low = Self.hexNibble(characters[index + 1])
      else { throw CorpusError.invalidHex }
      append((high << 4) | low)
    }
  }

  var hex: String {
    map { String(format: "%02x", $0) }.joined()
  }

  static func hexNibble(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48 ... 57: byte - 48
    case 65 ... 70: byte - 55
    case 97 ... 102: byte - 87
    default: nil
    }
  }
}
