// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

internal func filler(_ byte: UInt8, _ count: Int) -> Data {
  Data(repeating: byte, count: count)
}

// MARK: - Unit 1: pairing offer

internal func makeOffer() throws -> PairingOffer {
  try PairingOffer(
    offerIdentifier: filler(0x01, OfferLimit.offerIdentifierSize),
    pairingSecret: filler(0x02, OfferLimit.pairingSecretSize),
    suites: [mandatoryPairingSuite],
    profiles: ["fi.eid.card-status.v1", "fi.eid.authentication.v1"],
    transports: [
      TransportCandidate(
        profile: "fi.refineid.stream.v1",
        candidateIdentifier: "stream-1",
        parameters: ["endpoints": .array([.text("192.0.2.1:47110")])]
      ),
      TransportCandidate(
        profile: "apple-peer-v1", candidateIdentifier: "apple-peer-v1.nearby"),
    ],
    offerLifetimeMilliseconds: 60_000
  )
}

internal func makePairRecord() throws -> PairRecord {
  try PairRecord(
    pairIdentifier: filler(0x11, PairRecordSize.pairIdentifier),
    rendezvousToken: filler(0x22, PairRecordSize.rendezvousToken),
    role: .requester,
    localStaticPrivate: filler(0x33, PairRecordSize.staticKey),
    localStaticPublic: filler(0x44, PairRecordSize.staticKey),
    remoteStaticPublic: filler(0x55, PairRecordSize.staticKey),
    grantsHash: filler(0x66, PairRecordSize.grantsHash),
    profiles: [.cardStatus, .authentication],
    transport: PairTransportBinding(
      profile: "fi.refineid.stream.v1",
      candidateIdentifier: "stream-1",
      parameters: ["endpoints": .array([.text("192.0.2.1:47110")])]
    ),
    createdAtMilliseconds: 1_700_000_000_000
  )
}
