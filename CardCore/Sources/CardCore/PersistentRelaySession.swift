// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(MultipeerConnectivity)
  @preconcurrency import MultipeerConnectivity
  import os

  /// A single encrypted MultipeerConnectivity transport.
  ///
  /// The transport carries opaque RAPP frames and never decodes protocol or
  /// card-operation data. Peer authentication belongs to RAPP rather than
  /// MultipeerConnectivity discovery.
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

    /// Builds a channel for one role that reports to one owner.
    @preconcurrency
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

    /// Advertises or browses, by role.
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

    /// Sends one opaque frame to the connected peer, or throws.
    public func send(_ frame: Data) throws {
      guard !session.connectedPeers.isEmpty else {
        throw PersistentRelayTransportError.disconnected
      }
      do {
        try session.send(
          frame,
          toPeers: session.connectedPeers,
          with: .reliable
        )
      } catch let error as PersistentRelayTransportError {
        throw error
      } catch {
        throw PersistentRelayTransportError.send(String(describing: error))
      }
    }

    /// Stops discovery, disconnects, and reports the channel closed.
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

    /// Tracks the one connection and re-invites a lost first attempt.
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

    /// Hands one opaque frame to the owner without interpreting it.
    public func session(
      _: MCSession,
      didReceive data: Data,
      fromPeer _: MCPeerID
    ) {
      onEvent(.frame(data))
    }

    /// Streams are not part of the protocol; ignored.
    public func session(
      _: MCSession,
      didReceive _: InputStream,
      withName _: String,
      fromPeer _: MCPeerID
    ) {}

    /// Resources are not part of the protocol; ignored.
    public func session(
      _: MCSession,
      didStartReceivingResourceWithName _: String,
      fromPeer _: MCPeerID,
      with _: Progress
    ) {}

    /// Resources are not part of the protocol; ignored.
    public func session(
      _: MCSession,
      didFinishReceivingResourceWithName _: String,
      fromPeer _: MCPeerID,
      at _: URL?,
      withError _: (any Error)?
    ) {}

    /// Accepts the inviter into the encrypted session.
    ///
    /// Acceptance is currently unconditional: there is no pairing and
    /// no peer allowlist yet. That gap is the release blocker keeping
    /// FEATURE_IPHONE_RELAY out of shipping builds.
    public func advertiser(
      _: MCNearbyServiceAdvertiser,
      didReceiveInvitationFromPeer peerID: MCPeerID,
      withContext _: Data?,
      invitationHandler: (Bool, MCSession?) -> Void
    ) {
      trace("accepted invitation from \(peerID.displayName)")
      invitationHandler(true, session)
    }

    /// Reports a failed advertising start as a closed channel.
    public func advertiser(
      _: MCNearbyServiceAdvertiser,
      didNotStartAdvertisingPeer error: any Error
    ) {
      trace("advertising failed \(String(describing: error))")
      finish(.startup(String(describing: error)))
    }

    /// Invites the first advertised peer found.
    public func browser(
      _: MCNearbyServiceBrowser,
      foundPeer peerID: MCPeerID,
      withDiscoveryInfo _: [String: String]?
    ) {
      trace("found \(peerID.displayName)")
      lastFoundPeer = peerID
      invite(peerID)
    }

    /// Forgets a vanished peer so a stale invite is not retried.
    public func browser(_: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
      trace("lost \(peerID.displayName)")
      if lastFoundPeer?.displayName == peerID.displayName {
        lastFoundPeer = nil
      }
    }

    /// Reports a failed browsing start as a closed channel.
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
#endif
