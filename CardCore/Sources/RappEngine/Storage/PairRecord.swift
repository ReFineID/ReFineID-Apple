// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Storage-format version of a persisted pairing.
internal let pairRecordFormatVersion: UInt64 = 2

/// One durable pairing, as stored on this device only.
internal struct PairRecord: Equatable {
  internal let pairIdentifier: Data
  internal let rendezvousToken: Data
  internal let role: EndpointRole
  internal let localStaticPrivate: Data
  internal let localStaticPublic: Data
  internal let remoteStaticPublic: Data
  internal let grantsHash: Data
  internal let profiles: [ProfileName]
  internal let transport: PairTransportBinding
  internal let createdAtMilliseconds: UInt64

  internal init(
    pairIdentifier: Data,
    rendezvousToken: Data,
    role: EndpointRole,
    localStaticPrivate: Data,
    localStaticPublic: Data,
    remoteStaticPublic: Data,
    grantsHash: Data,
    profiles: [ProfileName],
    transport: PairTransportBinding,
    createdAtMilliseconds: UInt64
  ) throws {
    guard pairIdentifier.count == PairRecordSize.pairIdentifier,
      rendezvousToken.count == PairRecordSize.rendezvousToken,
      grantsHash.count == PairRecordSize.grantsHash,
      localStaticPrivate.count == PairRecordSize.staticKey,
      localStaticPublic.count == PairRecordSize.staticKey,
      remoteStaticPublic.count == PairRecordSize.staticKey
    else { throw PairRecordError.invalidInput }
    guard !localStaticPrivate.allSatisfy({ $0 == 0 }),
      !localStaticPublic.allSatisfy({ $0 == 0 }),
      !remoteStaticPublic.allSatisfy({ $0 == 0 })
    else { throw PairRecordError.invalidInput }
    guard !profiles.isEmpty else { throw PairRecordError.invalidInput }
    guard !transport.profile.isEmpty, !transport.candidateIdentifier.isEmpty else {
      throw PairRecordError.invalidInput
    }
    self.pairIdentifier = pairIdentifier
    self.rendezvousToken = rendezvousToken
    self.role = role
    self.localStaticPrivate = localStaticPrivate
    self.localStaticPublic = localStaticPublic
    self.remoteStaticPublic = remoteStaticPublic
    self.grantsHash = grantsHash
    self.profiles = profiles
    self.transport = transport
    self.createdAtMilliseconds = createdAtMilliseconds
  }

  /// Every key a stored record may carry, and must carry in full.
  private static let expectedKeys = [
    "format_version", "pair_id", "rendezvous_token", "role", "local_static_private",
    "local_static_public", "remote_static_public", "grants_hash", "profiles", "transport_profile",
    "candidate_id", "transport_parameters", "created_at_ms",
  ]

  internal func encoded() throws -> Data {
    let value = WireValue.map([
      "format_version": .unsigned(pairRecordFormatVersion),
      "pair_id": .bytes(pairIdentifier),
      "rendezvous_token": .bytes(rendezvousToken),
      "role": .text(role.rawValue),
      "local_static_private": .bytes(localStaticPrivate),
      "local_static_public": .bytes(localStaticPublic),
      "remote_static_public": .bytes(remoteStaticPublic),
      "grants_hash": .bytes(grantsHash),
      "profiles": .array(profiles.map { .text($0.rawValue) }),
      "transport_profile": .text(transport.profile),
      "candidate_id": .text(transport.candidateIdentifier),
      "transport_parameters": .map(transport.parameters),
      "created_at_ms": .unsigned(createdAtMilliseconds),
    ])
    do {
      return try value.encoded()
    } catch {
      throw PairRecordError.invalidInput
    }
  }

  internal static func decode(_ bytes: Data) throws -> PairRecord {
    guard let decoded = try? decodeDeterministicCbor(bytes),
      case .map(var map) = decoded
    else { throw PairRecordError.invalidInput }
    guard map.keys.allSatisfy(expectedKeys.contains) else { throw PairRecordError.invalidInput }
    guard try takeUnsigned(&map, "format_version") == pairRecordFormatVersion else {
      throw PairRecordError.invalidInput
    }
    let pairIdentifier = try takeBytes(&map, "pair_id")
    let rendezvousToken = try takeBytes(&map, "rendezvous_token")
    guard let role = EndpointRole(rawValue: try takeText(&map, "role")) else {
      throw PairRecordError.invalidInput
    }
    let localStaticPrivate = try takeBytes(&map, "local_static_private")
    let localStaticPublic = try takeBytes(&map, "local_static_public")
    let remoteStaticPublic = try takeBytes(&map, "remote_static_public")
    let grantsHash = try takeBytes(&map, "grants_hash")
    let profiles = try takeTextArray(&map, "profiles").map { name -> ProfileName in
      guard let profile = ProfileName(rawValue: name) else { throw PairRecordError.invalidInput }
      return profile
    }
    let transport = PairTransportBinding(
      profile: try takeText(&map, "transport_profile"),
      candidateIdentifier: try takeText(&map, "candidate_id"),
      parameters: try takeMap(&map, "transport_parameters")
    )
    let createdAtMilliseconds = try takeUnsigned(&map, "created_at_ms")
    guard map.isEmpty else { throw PairRecordError.invalidInput }
    return try PairRecord(
      pairIdentifier: pairIdentifier,
      rendezvousToken: rendezvousToken,
      role: role,
      localStaticPrivate: localStaticPrivate,
      localStaticPublic: localStaticPublic,
      remoteStaticPublic: remoteStaticPublic,
      grantsHash: grantsHash,
      profiles: profiles,
      transport: transport,
      createdAtMilliseconds: createdAtMilliseconds
    )
  }
}
