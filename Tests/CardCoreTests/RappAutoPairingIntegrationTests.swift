// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import Foundation
  import RappEngine
  import Testing

  @Suite("RappAutoPairingIntegrationTests")
  internal struct RappAutoPairingIntegrationTests {
    private static let signature = Data([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02])

    @Test("Complete end-to-end zero-touch autopairing, Noise session handshake, and signing")
    internal func testAutoPairingAndEndToEndSessionCrossing() async throws {
      let storage = InMemoryCloudStorage()

      // 1. Initialize iPhone (Card Holder) & Mac (Requester)
      let phonePrefix = "fi.refineid.test.e2e.phone.\(UUID().uuidString)"
      let phoneID = try makeIdentity(
        service: "\(phonePrefix).identity", name: "iPhone", model: "iPhone16,1", seed: 0x55)
      let phoneVault = RappDeviceVault(accessGroup: nil, servicePrefix: phonePrefix)
      let phoneCoordinator = RappCloudSyncCoordinator(
        localIdentity: phoneID, localRole: .holder, cloudStorage: storage)
      try await phoneCoordinator.publishLocalDevice()

      let macPrefix = "fi.refineid.test.e2e.mac.\(UUID().uuidString)"
      let macID = try makeIdentity(
        service: "\(macPrefix).identity", name: "Mac", model: "Mac15,3", seed: 0x66)
      let macVault = RappDeviceVault(accessGroup: nil, servicePrefix: macPrefix)
      let macCoordinator = RappCloudSyncCoordinator(
        localIdentity: macID, localRole: .requester, cloudStorage: storage)

      // 2. Reconcile both sides via iCloud sync
      let macPairs = try await macCoordinator.reconcileVault(vault: macVault)
      let phonePairs = try await phoneCoordinator.reconcileVault(vault: phoneVault)
      #expect(macPairs.count == 1)
      #expect(phonePairs.count == 1)
      #expect(macPairs[0].metadata().pairId == phonePairs[0].metadata().pairId)

      // 3. Establish live session over loopback wire using the auto-paired records
      let requesterSession = try SignRelaySession(
        role: .requester, pair: macPairs[0], vault: macVault)
      let proxySession = try SignRelaySession(role: .proxy, pair: phonePairs[0], vault: phoneVault)

      let wire = SignRelayWire(requester: requesterSession, proxy: proxySession)
      await wire.answerWith { request in
        .signatureResponse(requestID: request.requestID, signature: Self.signature)
      }
      try await wire.establish()

      #expect(await requesterSession.isEstablished)
      #expect(await proxySession.isEstablished)

      // 4. Execute signature request across the secure channel
      let requestID = UUID()
      let answer = try await wire.ask(
        .signatureRequest(
          requestID: requestID,
          profile: .ecdsaP256,
          algorithm: .ecdsaSHA256,
          digest: Data(repeating: 0xEE, count: 32)
        )
      )

      #expect(answer == .signatureResponse(requestID: requestID, signature: Self.signature))
    }

    private func makeIdentity(service: String, name: String, model: String, seed: UInt8) throws
      -> RappDeviceIdentity
    {
      try RappDeviceIdentity(
        accessGroup: nil,
        service: service,
        deviceName: name,
        modelName: model,
        fixedPrivateKey: Data(repeating: seed, count: 32),
        fixedDeviceID: UUID()
      )
    }
  }
#endif
