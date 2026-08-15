// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(MultipeerConnectivity)
  @preconcurrency import MultipeerConnectivity
  import os
#endif

/// Stable coordinates shared by the hosting app and persistent token driver.
public enum PersistentTokenIdentity {
  public static let classID = "fi.refineid.ReFineID.token"
  public static let certificateObjectID = "authentication-certificate"
  public static let keyObjectID = "authentication-key"
}

/// The card-key facts needed to resolve a signature without rereading the
/// certificate during the short NFC signing field.
public enum PersistentRelayCardProfile: String, Codable, Sendable {
  case ecdsaP256
  case ecdsaP384
  case rsa2048
  case rsa3072

  public init(_ profile: CardKeyProfile) {
    self = switch profile {
    case .ecdsaP256: .ecdsaP256
    case .ecdsaP384: .ecdsaP384
    case .rsa2048: .rsa2048
    case .rsa3072: .rsa3072
    }
  }

  public var cardKeyProfile: CardKeyProfile {
    switch self {
    case .ecdsaP256: .ecdsaP256
    case .ecdsaP384: .ecdsaP384
    case .rsa2048: .rsa2048
    case .rsa3072: .rsa3072
    }
  }
}

/// The exact MSE:SET shape already resolved from CryptoTokenKit's algorithm
/// chain. Only public signature parameters cross the relay.
public enum PersistentRelaySigningAlgorithm: String, Codable, Sendable {
  case ecdsaSHA224
  case ecdsaSHA256
  case ecdsaSHA384
  case ecdsaSHA512
  case rsaPkcs1SHA256
  case rsaPkcs1SHA384
  case rsaPkcs1SHA512
  case rsaPssSHA256

  public init?(_ algorithm: SigningAlgorithm) {
    switch (algorithm.scheme, algorithm.hash) {
    case (.ecdsa, .sha224): self = .ecdsaSHA224
    case (.ecdsa, .sha256): self = .ecdsaSHA256
    case (.ecdsa, .sha384): self = .ecdsaSHA384
    case (.ecdsa, .sha512): self = .ecdsaSHA512
    case (.rsaPkcs1, .sha256): self = .rsaPkcs1SHA256
    case (.rsaPkcs1, .sha384): self = .rsaPkcs1SHA384
    case (.rsaPkcs1, .sha512): self = .rsaPkcs1SHA512
    case (.rsaPss, .sha256): self = .rsaPssSHA256
    default: return nil
    }
  }

  public var signingAlgorithm: SigningAlgorithm {
    switch self {
    case .ecdsaSHA224: SigningAlgorithm(hash: .sha224, scheme: .ecdsa)
    case .ecdsaSHA256: SigningAlgorithm(hash: .sha256, scheme: .ecdsa)
    case .ecdsaSHA384: SigningAlgorithm(hash: .sha384, scheme: .ecdsa)
    case .ecdsaSHA512: SigningAlgorithm(hash: .sha512, scheme: .ecdsa)
    case .rsaPkcs1SHA256: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1)
    case .rsaPkcs1SHA384: SigningAlgorithm(hash: .sha384, scheme: .rsaPkcs1)
    case .rsaPkcs1SHA512: SigningAlgorithm(hash: .sha512, scheme: .rsaPkcs1)
    case .rsaPssSHA256: SigningAlgorithm(hash: .sha256, scheme: .rsaPss)
    }
  }
}

/// A typed failure. Credentials and raw APDUs are deliberately absent.
public enum PersistentRelayFailure: Codable, Equatable, Error, Sendable {
  case busy
  case cardUnavailable
  case communication
  case invalidCard
  case missingCardAccessNumber
  case missingPIN1
  case pin1Blocked
  case pin1Rejected(remaining: Int?)
  case pin1RetryFloor
  case unsupportedAlgorithm
  case wrongCardAccessNumber
}

/// One correlated request or response on the encrypted local relay.
public enum PersistentRelayMessage: Codable, Equatable, Sendable {
  case identityRequest(id: UUID)
  case identityResponse(id: UUID, certificateDER: Data)
  case signatureRequest(
    id: UUID,
    profile: PersistentRelayCardProfile,
    algorithm: PersistentRelaySigningAlgorithm,
    digest: Data
  )
  case signatureResponse(id: UUID, signature: Data)
  case failure(id: UUID, reason: PersistentRelayFailure)

  public var requestID: UUID {
    switch self {
    case .identityRequest(let id), .identityResponse(let id, _),
      .signatureRequest(let id, _, _, _), .signatureResponse(let id, _),
      .failure(let id, _):
      id
    }
  }

  fileprivate func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }

  fileprivate static func decoded(_ data: Data) throws -> Self {
    try JSONDecoder().decode(Self.self, from: data)
  }
}

#if canImport(MultipeerConnectivity)
  public enum PersistentRelayRole: Sendable {
    case cardHolder
    case host
  }

  public enum PersistentRelayTransportError: Error, Sendable {
    case cancelled
    case codec(String)
    case disconnected
    case send(String)
    case startup(String)
    case timedOut
  }

  public enum PersistentRelayEvent: Sendable {
    case connected
    case message(PersistentRelayMessage)
    case closed(PersistentRelayTransportError)
  }

  /// A single encrypted MultipeerConnectivity channel. The phone advertises;
  /// the Mac host or token extension browses and invites it.
  public final class PersistentRelaySession: NSObject, @unchecked Sendable,
    MCSessionDelegate, MCNearbyServiceAdvertiserDelegate,
    MCNearbyServiceBrowserDelegate
  {
    private static let serviceType = "refineid-rly"
    private static let invitationRetry: TimeInterval = 3
    private static let invitationTimeout: TimeInterval = 10

    private let role: PersistentRelayRole
    private let localPeer: MCPeerID
    private let session: MCSession
    private let onEvent: @Sendable (PersistentRelayEvent) -> Void
    private let closed = OSAllocatedUnfairLock(initialState: false)
    private let everConnected = OSAllocatedUnfairLock(initialState: false)
    private let lastInviteAt = OSAllocatedUnfairLock<Date?>(initialState: nil)
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var lastFoundPeer: MCPeerID?

    public init(
      role: PersistentRelayRole,
      displayName: String,
      onEvent: @escaping @Sendable (PersistentRelayEvent) -> Void
    ) {
      self.role = role
      self.localPeer = Self.persistentPeer(displayName: displayName, role: role)
      self.session = MCSession(
        peer: localPeer,
        securityIdentity: nil,
        encryptionPreference: .required
      )
      self.onEvent = onEvent
      super.init()
      session.delegate = self
    }

    private static func persistentPeer(
      displayName: String,
      role: PersistentRelayRole
    ) -> MCPeerID {
      let roleName = role == .cardHolder ? "card" : "host"
      let key = "fi.refineid.persistent-relay.\(roleName).\(displayName)"
      let defaults = UserDefaults.standard
      if let data = defaults.data(forKey: key),
        let peer = try? NSKeyedUnarchiver.unarchivedObject(
          ofClass: MCPeerID.self,
          from: data
        )
      {
        return peer
      }
      let peer = MCPeerID(displayName: displayName)
      if let data = try? NSKeyedArchiver.archivedData(
        withRootObject: peer,
        requiringSecureCoding: true
      ) {
        defaults.set(data, forKey: key)
      }
      return peer
    }

    public func start() {
      switch role {
      case .cardHolder:
        let advertiser = MCNearbyServiceAdvertiser(
          peer: localPeer,
          discoveryInfo: nil,
          serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
      case .host:
        let browser = MCNearbyServiceBrowser(
          peer: localPeer,
          serviceType: Self.serviceType
        )
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
      }
      trace("started role=\(role)")
    }

    public func send(_ message: PersistentRelayMessage) throws {
      guard !session.connectedPeers.isEmpty else {
        throw PersistentRelayTransportError.disconnected
      }
      do {
        try session.send(
          try message.encoded(),
          toPeers: session.connectedPeers,
          with: .reliable
        )
      } catch let error as PersistentRelayTransportError {
        throw error
      } catch {
        throw PersistentRelayTransportError.send(String(describing: error))
      }
    }

    public func cancel() {
      advertiser?.stopAdvertisingPeer()
      browser?.stopBrowsingForPeers()
      session.disconnect()
      finish(.cancelled)
    }

    private func finish(_ error: PersistentRelayTransportError) {
      let wasClosed = closed.withLock { value -> Bool in
        if value { return true }
        value = true
        return false
      }
      guard !wasClosed else { return }
      trace("closed \(String(describing: error))")
      advertiser?.stopAdvertisingPeer()
      browser?.stopBrowsingForPeers()
      onEvent(.closed(error))
    }

    private func invite(_ peer: MCPeerID) {
      guard let browser, session.connectedPeers.isEmpty else { return }
      let shouldInvite = lastInviteAt.withLock { last -> Bool in
        let now = Date()
        if let last, now.timeIntervalSince(last) < Self.invitationRetry {
          return false
        }
        last = now
        return true
      }
      guard shouldInvite else { return }
      browser.invitePeer(
        peer,
        to: session,
        withContext: nil,
        timeout: Self.invitationTimeout
      )
      trace("invited \(peer.displayName)")
    }

    public func session(
      _: MCSession,
      peer peerID: MCPeerID,
      didChange state: MCSessionState
    ) {
      switch state {
      case .connected:
        everConnected.withLock { $0 = true }
        onEvent(.connected)
        trace("connected \(peerID.displayName)")
      case .notConnected:
        trace("not connected \(peerID.displayName)")
        if everConnected.withLock({ $0 }) {
          finish(.disconnected)
        } else if let peer = lastFoundPeer {
          invite(peer)
        }
      case .connecting:
        trace("connecting \(peerID.displayName)")
      @unknown default:
        break
      }
    }

    public func session(
      _: MCSession,
      didReceive data: Data,
      fromPeer _: MCPeerID
    ) {
      do {
        onEvent(.message(try PersistentRelayMessage.decoded(data)))
      } catch {
        finish(.codec(String(describing: error)))
      }
    }

    public func session(
      _: MCSession,
      didReceive _: InputStream,
      withName _: String,
      fromPeer _: MCPeerID
    ) {}

    public func session(
      _: MCSession,
      didStartReceivingResourceWithName _: String,
      fromPeer _: MCPeerID,
      with _: Progress
    ) {}

    public func session(
      _: MCSession,
      didFinishReceivingResourceWithName _: String,
      fromPeer _: MCPeerID,
      at _: URL?,
      withError _: (any Error)?
    ) {}

    public func advertiser(
      _: MCNearbyServiceAdvertiser,
      didReceiveInvitationFromPeer peerID: MCPeerID,
      withContext _: Data?,
      invitationHandler: (Bool, MCSession?) -> Void
    ) {
      trace("accepted invitation from \(peerID.displayName)")
      invitationHandler(true, session)
    }

    public func advertiser(
      _: MCNearbyServiceAdvertiser,
      didNotStartAdvertisingPeer error: any Error
    ) {
      trace("advertising failed \(String(describing: error))")
      finish(.startup(String(describing: error)))
    }

    public func browser(
      _: MCNearbyServiceBrowser,
      foundPeer peerID: MCPeerID,
      withDiscoveryInfo _: [String: String]?
    ) {
      trace("found \(peerID.displayName)")
      lastFoundPeer = peerID
      invite(peerID)
    }

    public func browser(_: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
      trace("lost \(peerID.displayName)")
      if lastFoundPeer?.displayName == peerID.displayName {
        lastFoundPeer = nil
      }
    }

    public func browser(
      _: MCNearbyServiceBrowser,
      didNotStartBrowsingForPeers error: any Error
    ) {
      trace("browsing failed \(String(describing: error))")
      finish(.startup(String(describing: error)))
    }

    private func trace(_ message: String) {
      #if DEBUG
        print("[persistent-relay] \(message)")
        fflush(stdout)
      #endif
    }
  }

  /// One synchronous request bridge for CryptoTokenKit's synchronous sign
  /// callback. A client object is intentionally single-use.
  public final class PersistentRelayClient: @unchecked Sendable {
    private struct State: Sendable {
      var completed = false
      var request: PersistentRelayMessage?
      var response: PersistentRelayMessage?
      var error: PersistentRelayTransportError?
    }

    private let displayName: String
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let completed = DispatchSemaphore(value: 0)
    private lazy var session = PersistentRelaySession(
      role: .host,
      displayName: displayName
    ) { [weak self] event in
      self?.receive(event)
    }

    public init(displayName: String) {
      self.displayName = displayName
    }

    public func perform(
      _ request: PersistentRelayMessage,
      timeout: TimeInterval = 120
    ) throws -> PersistentRelayMessage {
      let accepted = state.withLock { state -> Bool in
        guard state.request == nil else { return false }
        state.request = request
        return true
      }
      guard accepted else {
        throw PersistentRelayTransportError.send("client is single-use")
      }
      session.start()
      guard completed.wait(timeout: .now() + timeout) == .success else {
        session.cancel()
        throw PersistentRelayTransportError.timedOut
      }
      session.cancel()
      return try state.withLock { state in
        if let response = state.response { return response }
        throw state.error ?? PersistentRelayTransportError.disconnected
      }
    }

    private func receive(_ event: PersistentRelayEvent) {
      switch event {
      case .connected:
        guard let request = state.withLock({ $0.request }) else { return }
        do {
          try session.send(request)
        } catch let error as PersistentRelayTransportError {
          finish(error: error)
        } catch {
          finish(error: .send(String(describing: error)))
        }
      case .message(let message):
        guard
          let requestID = state.withLock({ $0.request?.requestID }),
          requestID == message.requestID
        else { return }
        finish(response: message)
      case .closed(let error):
        finish(error: error)
      }
    }

    private func finish(
      response: PersistentRelayMessage? = nil,
      error: PersistentRelayTransportError? = nil
    ) {
      let shouldSignal = state.withLock { state -> Bool in
        guard !state.completed else { return false }
        state.completed = true
        state.response = response
        state.error = error
        return true
      }
      if shouldSignal { completed.signal() }
    }
  }
#endif
