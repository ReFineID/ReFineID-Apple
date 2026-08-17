import Foundation
import Testing

@Suite("RAPP independent session conformance corpus")
struct RappSessionConformanceCorpusTests {
  private static let supportedWireVersion: [UInt16] = [0, 1]

  @Test
  func exactDirectionalSequenceAndSessionBindingMatchCorpus() throws {
    for vector in try Self.corpus().sequenceGuard {
      let guardSessionID = try Data(sessionHex: vector.guardSessionIdHex)
      var guardState = IndependentSequenceGuard(sessionID: guardSessionID)

      for sequence in vector.acceptedSequences {
        #expect(
          guardState.accept(sessionID: guardSessionID, sequence: sequence) == .accepted,
          "\(vector.name): invalid accepted prefix at \(sequence)"
        )
      }

      let incomingSessionID = try Data(sessionHex: vector.incomingSessionIdHex)
      #expect(
        guardState.accept(
          sessionID: incomingSessionID,
          sequence: vector.incomingSequence
        ).rawValue == vector.expected,
        "\(vector.name): candidate decision"
      )
      #expect(
        guardState.accept(
          sessionID: guardSessionID,
          sequence: vector.expectedNextReceive
        ) == .accepted,
        "\(vector.name): rejected candidate advanced the guard"
      )
    }
  }

  @Test
  func visibleWireVersionRejectsDowngradesAndUnknownUpgrades() throws {
    for vector in try Self.corpus().wireVersion {
      let decision =
        vector.version == Self.supportedWireVersion
        ? "accepted"
        : "unsupported_version"
      #expect(decision == vector.expected, "\(vector.name): wire version decision")
    }
  }

  @Test
  func operationProfilesCannotExceedAuthenticatedPairingGrants() throws {
    for vector in try Self.corpus().grantEnforcement {
      let decision =
        Set(vector.grantedProfiles).contains(vector.requestedProfile)
        ? "accepted"
        : "profile_not_granted"
      #expect(decision == vector.expected, "\(vector.name): grant decision")
    }
  }

  private static func corpus() throws -> SessionCorpus {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url =
      repository
      .appendingPathComponent("Documentation")
      .appendingPathComponent("rapp-conformance")
      .appendingPathComponent("rapp-v26.8.16.85.json")
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(SessionCorpus.self, from: Data(contentsOf: url))
  }
}

private struct SessionCorpus: Decodable {
  let sequenceGuard: [SequenceVector]
  let wireVersion: [WireVersionVector]
  let grantEnforcement: [GrantVector]
}

private struct SequenceVector: Decodable {
  let name: String
  let guardSessionIdHex: String
  let acceptedSequences: [UInt64]
  let incomingSessionIdHex: String
  let incomingSequence: UInt64
  let expected: String
  let expectedNextReceive: UInt64
}

private struct WireVersionVector: Decodable {
  let name: String
  let version: [UInt16]
  let expected: String
}

private struct GrantVector: Decodable {
  let name: String
  let grantedProfiles: [String]
  let requestedProfile: String
  let expected: String
}

private enum IndependentSequenceDecision: String {
  case accepted
  case wrongSession = "wrong_session"
  case wrongSequence = "wrong_sequence"
}

private struct IndependentSequenceGuard {
  let sessionID: Data
  private(set) var nextReceive: UInt64 = 0

  mutating func accept(
    sessionID incomingSessionID: Data,
    sequence: UInt64
  ) -> IndependentSequenceDecision {
    guard incomingSessionID == sessionID else { return .wrongSession }
    guard sequence == nextReceive else { return .wrongSequence }
    guard nextReceive < UInt64.max else { return .wrongSequence }
    nextReceive += 1
    return .accepted
  }
}

extension Data {
  fileprivate init(sessionHex value: String) throws {
    guard value.count == 32, value.count.isMultiple(of: 2) else {
      throw SessionCorpusError.invalidHex
    }
    var bytes = [UInt8]()
    bytes.reserveCapacity(value.count / 2)
    var index = value.startIndex
    while index < value.endIndex {
      let next = value.index(index, offsetBy: 2)
      guard let byte = UInt8(value[index..<next], radix: 16) else {
        throw SessionCorpusError.invalidHex
      }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}

private enum SessionCorpusError: Error {
  case invalidHex
}
