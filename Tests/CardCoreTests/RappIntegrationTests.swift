// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing
@testable import CardCore

#if canImport(ReFineIDRapp)
  @Suite
  internal struct RappIntegrationTests {
    private enum TestFailure: Error {
      case receiverMissing
      case pairingClosed(RappPairingCoordinator.CloseReason)
      case pairingEndedWithoutRecord
      case unexpectedTransportError
    }

    private actor FrameEndpoint {
      typealias Receiver = @Sendable (Data) async -> Void

      private var receiver: Receiver?
      private var frames: [Data] = []
      private var closeCount = 0

      func install(_ receiver: @escaping Receiver) {
        self.receiver = receiver
      }

      func send(_ frame: Data) async throws {
        frames.append(frame)
        guard let receiver else { throw TestFailure.receiverMissing }
        await receiver(frame)
      }

      func close() {
        closeCount += 1
      }

      func snapshot() -> (frames: [Data], closeCount: Int) {
        (frames, closeCount)
      }
    }

    private actor TransportRecorder {
      private var frames: [Data] = []
      private var closeCount = 0

      func record(_ frame: Data) {
        frames.append(frame)
      }

      func close() {
        closeCount += 1
      }

      func snapshot() -> (frames: [Data], closeCount: Int) {
        (frames, closeCount)
      }
    }

    @Test
    internal func closureTransportPreservesFramesAndClosesExactlyOnce() async throws {
      let recorder = TransportRecorder()
      let transport = RappClosureFrameTransport(
        sender: { frame in await recorder.record(frame) },
        closer: { await recorder.close() }
      )
      let frame = Data([0x01, 0x02, 0x03])

      try await transport.send(frame)
      await transport.close()
      await transport.close()

      let snapshot = await recorder.snapshot()
      #expect(snapshot.frames == [frame])
      #expect(snapshot.closeCount == 1)

      do {
        try await transport.send(Data([0x04]))
        Issue.record("A closed RAPP transport accepted another frame")
      } catch is CancellationError {
        // Expected: a closed transport cannot silently reopen.
      } catch {
        Issue.record("A closed RAPP transport returned the wrong error")
      }
    }

    @Test
    internal func cardOperationMappingsAreCompleteAndRoundTrip() throws {
      let profiles: [CardKeyProfile] = [
        .ecdsaP256,
        .ecdsaP384,
        .rsa2048,
        .rsa3072,
      ]
      for profile in profiles {
        #expect(RappOperationDriver.KeyProfile(profile).cardKeyProfile == profile)
      }

      let algorithms = [
        SigningAlgorithm(hash: .sha224, scheme: .ecdsa),
        SigningAlgorithm(hash: .sha256, scheme: .ecdsa),
        SigningAlgorithm(hash: .sha384, scheme: .ecdsa),
        SigningAlgorithm(hash: .sha512, scheme: .ecdsa),
        SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1),
        SigningAlgorithm(hash: .sha384, scheme: .rsaPkcs1),
        SigningAlgorithm(hash: .sha512, scheme: .rsaPkcs1),
        SigningAlgorithm(hash: .sha256, scheme: .rsaPss),
      ]
      for algorithm in algorithms {
        let mapped = try #require(RappOperationDriver.SignatureAlgorithm(algorithm))
        #expect(mapped.signingAlgorithm.hash == algorithm.hash)
        #expect(mapped.signingAlgorithm.scheme == algorithm.scheme)
      }

      #expect(RappOperationDriver.SignatureAlgorithm(
        SigningAlgorithm(hash: .sha224, scheme: .rsaPkcs1)
      ) == nil)
      #expect(RappOperationDriver.SignatureAlgorithm(
        SigningAlgorithm(hash: .sha384, scheme: .rsaPss)
      ) == nil)
    }

    @Test
    internal func swiftCoordinatorsPairThroughRustAndRevocationIsDurable() async throws {
      let profiles = [
        "fi.eid.card-status.v1",
        "fi.eid.authentication.v1",
        "fi.eid.document-signing.v1",
      ]
      let candidateID = "apple-peer-v1.nearby"
      let testID = UUID().uuidString
      let requesterPrefix = "fi.refineid.tests.rapp.\(testID).requester"
      let proxyPrefix = "fi.refineid.tests.rapp.\(testID).proxy"
      defer {
        Self.deleteKeychainServices(prefix: requesterPrefix)
        Self.deleteKeychainServices(prefix: proxyPrefix)
      }

      let requesterVault = RappDeviceVault(
        accessGroup: nil,
        servicePrefix: requesterPrefix
      )
      let proxyVault = RappDeviceVault(
        accessGroup: nil,
        servicePrefix: proxyPrefix
      )
      let requesterOutbound = FrameEndpoint()
      let proxyOutbound = FrameEndpoint()
      let requesterTransport = RappClosureFrameTransport(
        sender: { frame in try await requesterOutbound.send(frame) },
        closer: { await requesterOutbound.close() }
      )
      let proxyTransport = RappClosureFrameTransport(
        sender: { frame in try await proxyOutbound.send(frame) },
        closer: { await proxyOutbound.close() }
      )
      let requester = try RappPairingCoordinator.requester(
        profiles: profiles,
        candidates: [
          .init(
            profile: "apple-peer-v1",
            candidateID: candidateID,
            parametersCBOR: Data([0xA0])
          )
        ],
        selectedCandidateID: candidateID,
        offerLifetimeMilliseconds: 60_000,
        displayName: "Requester Mac",
        platform: "macOS",
        vault: requesterVault,
        transport: requesterTransport
      )
      let proxy = try RappPairingCoordinator.proxy(
        scannedOfferURI: try #require(requester.offerURI),
        selectedCandidateID: candidateID,
        displayName: "Authorizer iPhone",
        platform: "iOS",
        vault: proxyVault,
        transport: proxyTransport
      )
      await requesterOutbound.install { frame in await proxy.receive(frame) }
      await proxyOutbound.install { frame in await requester.receive(frame) }

      let requesterOutcome = Task {
        try await Self.approveAndAwaitPair(requester, profiles: profiles)
      }
      let proxyOutcome = Task {
        try await Self.approveAndAwaitPair(proxy, profiles: profiles)
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await proxy.transportConnected()
      await requester.transportConnected()
      let requesterSummary = try await requesterOutcome.value
      let proxySummary = try await proxyOutcome.value

      #expect(requesterSummary.pairID == proxySummary.pairID)
      #expect(requesterSummary.role == .requester)
      #expect(proxySummary.role == .proxy)
      #expect(Set(requesterSummary.profiles) == Set(profiles))
      #expect(Set(proxySummary.profiles) == Set(profiles))
      #expect(requesterSummary.transportProfile == "apple-peer-v1")
      #expect(requesterSummary.candidateID == candidateID)
      #expect(try requesterVault.loadPair(pairID: requesterSummary.pairID) != nil)
      #expect(try proxyVault.loadPair(pairID: proxySummary.pairID) != nil)

      let requesterFrames = await requesterOutbound.snapshot()
      let proxyFrames = await proxyOutbound.snapshot()
      #expect(!requesterFrames.frames.isEmpty)
      #expect(!proxyFrames.frames.isEmpty)
      #expect(requesterFrames.closeCount == 1)
      #expect(proxyFrames.closeCount == 1)

      let catalog = RappPairCatalog(vault: requesterVault)
      try await catalog.select(pairID: requesterSummary.pairID)
      #expect(try await catalog.selectedPair()?.pairID == requesterSummary.pairID)
      try await catalog.revoke(pairID: requesterSummary.pairID)
      #expect(try requesterVault.pairIsRevoked(pairID: requesterSummary.pairID))
      #expect(try await catalog.activePairs().isEmpty)
      #expect(try await catalog.selectedPair() == nil)
      #expect(try proxyVault.pairIsRevoked(pairID: proxySummary.pairID) == false)
    }

    private static func approveAndAwaitPair(
      _ coordinator: RappPairingCoordinator,
      profiles: [String]
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in coordinator.events {
        switch event {
        case .reviewPeer:
          await coordinator.approve(grantedProfiles: profiles)
        case .paired(let summary):
          return summary
        case .closed(let reason):
          throw TestFailure.pairingClosed(reason)
        case .offerReady:
          break
        }
      }
      throw TestFailure.pairingEndedWithoutRecord
    }

    private static func deleteKeychainServices(prefix: String) {
      for suffix in ["pair", "selection"] {
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "\(prefix).\(suffix)",
          kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
          kSecAttrSynchronizable as String: false,
        ]
        SecItemDelete(query as CFDictionary)
      }
    }
  }
#endif
