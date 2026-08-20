// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The relay reduced to what the card actually needs: one request, one
/// answer, performed at most once, over a channel that authenticates every
/// frame.
@Suite
internal struct SignRelayTests {

  // MARK: Static Properties

  private static let digest = Data(repeating: 0xA5, count: 32)
  private static let signature = Data([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02])

  // MARK: Static Functions

  private static func deleteJournal(vault: RappDeviceVault, pairID: Data) {
    for stored in (try? vault.loadProxy(pairID: pairID)) ?? [] {
      try? vault.acknowledgeProxyResult(
        pairID: pairID, operationID: stored.record, record: stored.record)
    }
  }

  private static func request(_ id: UUID) -> PersistentRelayMessage {
    .signatureRequest(
      id: id,
      profile: .ecdsaP256,
      algorithm: .ecdsaSHA256,
      digest: digest
    )
  }

  // MARK: Functions

  /// A card read that outlasts any probe interval still lands.
  ///
  /// This is the arrangement the session machinery beside this has never
  /// survived: the antenna takes seconds, and nothing here is counting.
  @Test
  internal func aSlowCardReadStillAnswers() async throws {
    let id = UUID()
    let proxy = SignRelayProxy(channel: SignRelayMarkerChannel()) { request in
      try? await Task.sleep(for: .seconds(7))
      return .signatureResponse(id: request.requestID, signature: Self.signature)
    }
    let requester = SignRelayRequester(channel: SignRelayMarkerChannel())

    let answer = try await requester.perform(
      Self.request(id),
      timeout: .seconds(30)
    ) { frame in
      Task {
        if let reply = try? await proxy.receive(frame) {
          try? await requester.receive(reply)
        }
      }
    }

    #expect(answer == .signatureResponse(id: id, signature: Self.signature))
  }

  /// The same request twice reaches the card once.
  ///
  /// The card's retry counter does not go back up, so this is the one
  /// guarantee worth the machinery it takes.
  @Test
  internal func aRepeatedRequestReachesTheCardOnce() async throws {
    let id = UUID()
    let performed = SignRelayPerformanceCounter()
    let proxy = SignRelayProxy(channel: SignRelayMarkerChannel()) { request in
      await performed.increment()
      return .signatureResponse(id: request.requestID, signature: Self.signature)
    }

    let channel = SignRelayMarkerChannel()
    let frame = channel.seal(try Self.request(id).encoded())
    let first = try await proxy.receive(frame)
    let second = try await proxy.receive(frame)

    let expected = PersistentRelayMessage.signatureResponse(id: id, signature: Self.signature)
    #expect(try PersistentRelayMessage.decoded(channel.open(#require(first))) == expected)
    #expect(try PersistentRelayMessage.decoded(channel.open(#require(second))) == expected)
    #expect(await performed.count == 1)
  }

  /// A restart between reaching the card and answering does not reach it
  /// again.
  ///
  /// The proxy that performed the operation is gone; a new one serving the
  /// same pairing answers from what the first one wrote down.
  @Test
  internal func aRestartDoesNotReachTheCardTwice() async throws {
    let id = UUID()
    let vault = RappDeviceVault(
      accessGroup: nil,
      servicePrefix: "fi.refineid.tests.slim.journal.\(UUID().uuidString)")
    let pairID = Data(repeating: 0x0C, count: 16)
    defer { Self.deleteJournal(vault: vault, pairID: pairID) }
    let journal = SignRelayVaultJournal(vault: vault, pairID: pairID)
    let performed = SignRelayPerformanceCounter()
    let channel = SignRelayMarkerChannel()
    let frame = channel.seal(try Self.request(id).encoded())

    let before = SignRelayProxy(channel: channel, journal: journal) { request in
      await performed.increment()
      return .signatureResponse(id: request.requestID, signature: Self.signature)
    }
    _ = try await before.receive(frame)

    // The process ends here, and a new proxy comes up on the same pairing.
    let after = SignRelayProxy(channel: channel, journal: journal) { request in
      await performed.increment()
      return .signatureResponse(id: request.requestID, signature: Self.signature)
    }
    let replayed = try await after.receive(frame)

    let expected = PersistentRelayMessage.signatureResponse(id: id, signature: Self.signature)
    #expect(try PersistentRelayMessage.decoded(channel.open(#require(replayed))) == expected)
    #expect(await performed.count == 1)
  }

  /// A frame that will not open ends the session and nothing else.
  @Test
  internal func anUnopenableFrameEndsOnlyTheSession() async throws {
    let requester = SignRelayRequester(channel: SignRelayMarkerChannel())
    await #expect(throws: SignRelayRequester.Failure.sessionEnded) {
      try await requester.receive(Data("not sealed".utf8))
    }
  }

  /// A peer that never answers gives up at the deadline.
  @Test
  internal func aSilentPeerTimesOut() async throws {
    let requester = SignRelayRequester(channel: SignRelayMarkerChannel())
    await #expect(throws: SignRelayRequester.Failure.timedOut) {
      try await requester.perform(
        Self.request(UUID()),
        timeout: .milliseconds(200)
      ) { _ in
        // The peer is silent by never being handed the frame.
      }
    }
  }
}
