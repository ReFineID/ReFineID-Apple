// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(Network) && canImport(RappEngine)
  import Foundation
  import Network
  import RappEngine

  #if canImport(MultipeerConnectivity)
    @preconcurrency import MultipeerConnectivity
  #endif

  /// Discovers and publishes local peer identity announcements over mDNS/Bonjour and MultipeerConnectivity.
  ///
  /// Enables instantaneous zero-touch pairing across local Wi-Fi, Apple Wireless Direct Link (AWDL),
  /// and Bluetooth without requiring manual pairing codes or cloud synchronization delays.
  public final class RappLocalDiscovery: @unchecked Sendable {
    // MARK: Constants

    private enum Constants {
      static let shortIDPrefixLength = 8
      static let publicKeyByteCount = 32
      static let lengthHeaderByteCount = 4
      static let maxPayloadByteCount = 65_536
    }

    /// The Bonjour service type for local device auto-pairing discovery.
    public static let serviceType = "_refineid-disc._tcp"

    // MARK: Properties

    private let localIdentity: RappDeviceIdentity
    private let localRole: RappDeviceRole
    private let onDiscovered: @Sendable (RappCloudDeviceRecord) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.local-discovery")
    private var listener: NWListener?
    private var browser: NWBrowser?
    #if canImport(MultipeerConnectivity)
      private var multipeerHelper: MultipeerDiscoveryHelper?
    #endif
    private var isCancelled = false
    private var contactedEndpoints = Set<String>()

    // MARK: Initialization

    /// Creates a local discovery instance for advertising and discovering nearby peers.
    @preconcurrency
    public init(
      localIdentity: RappDeviceIdentity,
      localRole: RappDeviceRole,
      onDiscovered: @escaping @Sendable (RappCloudDeviceRecord) -> Void
    ) {
      self.localIdentity = localIdentity
      self.localRole = localRole
      self.onDiscovered = onDiscovered
    }

    // MARK: Lifecycle

    /// Starts advertising the local device and browsing for local peers.
    public func start() {
      queue.async {
        guard !self.isCancelled else { return }
        self.startAdvertising()
        self.startBrowsing()
        #if canImport(MultipeerConnectivity)
          let helper = MultipeerDiscoveryHelper(
            localIdentity: self.localIdentity,
            localRole: self.localRole,
            onDiscovered: self.onDiscovered
          )
          helper.start()
          self.multipeerHelper = helper
        #endif
      }
    }

    /// Stops advertising and browsing.
    public func cancel() {
      queue.async {
        self.isCancelled = true
        self.listener?.cancel()
        self.listener = nil
        self.browser?.cancel()
        self.browser = nil
        #if canImport(MultipeerConnectivity)
          self.multipeerHelper?.cancel()
          self.multipeerHelper = nil
        #endif
      }
    }

    // MARK: Advertising

    private func startAdvertising() {
      var txtRecord = NWTXTRecord()
      txtRecord["devid"] = localIdentity.deviceID.uuidString
      txtRecord["name"] = localIdentity.deviceName
      txtRecord["model"] = localIdentity.modelName
      txtRecord["role"] = localRole == .holder ? "holder" : "requester"
      txtRecord["pk"] = localIdentity.publicKeyData.base64EncodedString()

      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true

      guard let madeListener = try? NWListener(using: parameters) else { return }
      let shortID = String(localIdentity.deviceID.uuidString.prefix(Constants.shortIDPrefixLength))
      madeListener.service = NWListener.Service(
        name: "ReFineID-\(shortID)",
        type: Self.serviceType,
        domain: nil,
        txtRecord: txtRecord
      )
      madeListener.newConnectionHandler = { [weak self] connection in
        guard let self else {
          connection.cancel()
          return
        }
        handleIncomingDiscovery(connection)
      }
      madeListener.start(queue: queue)
      self.listener = madeListener
    }

    // MARK: Browsing

    private func startBrowsing() {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true

      let madeBrowser = NWBrowser(
        for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
        using: parameters
      )

      madeBrowser.browseResultsChangedHandler = { [weak self] results, _ in
        guard let self else { return }
        for result in results {
          handleBrowseResult(result)
        }
      }

      madeBrowser.start(queue: queue)
      self.browser = madeBrowser
    }

    private func handleBrowseResult(_ result: NWBrowser.Result) {
      if case .bonjour(let txt) = result.metadata,
        let devIDString = txt["devid"],
        let devID = UUID(uuidString: devIDString),
        devID != localIdentity.deviceID,
        let name = txt["name"],
        let model = txt["model"],
        let roleString = txt["role"],
        let pkBase64 = txt["pk"],
        let pkData = Data(base64Encoded: pkBase64),
        pkData.count == Constants.publicKeyByteCount
      {
        let role: RappDeviceRole = (roleString == "holder") ? .holder : .requester
        let record = RappCloudDeviceRecord(
          deviceID: devID,
          deviceName: name,
          modelName: model,
          role: role,
          staticPublicKey: pkData,
          rendezvousToken: RappSameAccountPairBuilder.deriveRendezvousToken(
            publicKeyA: pkData,
            publicKeyB: pkData
          ),
          updatedAt: Date()
        )
        onDiscovered(record)
        return
      }

      // If TXT record is unavailable or delayed by mDNS multicast snooping, connect directly over TCP
      guard case .service(let name, _, _, _) = result.endpoint,
        name.hasPrefix("ReFineID-"),
        !name.contains(
          String(localIdentity.deviceID.uuidString.prefix(Constants.shortIDPrefixLength)))
      else { return }

      let endpointKey = "\(name)"
      guard contactedEndpoints.insert(endpointKey).inserted else { return }

      connectAndExchange(endpoint: result.endpoint)
    }

    private func connectAndExchange(endpoint: NWEndpoint) {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      let connection = NWConnection(to: endpoint, using: parameters)

      connection.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          let localRecord = makeLocalRecord()
          sendRecord(localRecord, over: connection)
          readRecord(from: connection) { [weak self] peerRecord in
            connection.cancel()
            guard let self, let peerRecord, peerRecord.deviceID != localIdentity.deviceID
            else { return }
            onDiscovered(peerRecord)
          }
        case .failed, .cancelled:
          connection.cancel()
        default:
          break
        }
      }

      connection.start(queue: queue)
    }

    private func handleIncomingDiscovery(_ connection: NWConnection) {
      connection.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          let localRecord = makeLocalRecord()
          sendRecord(localRecord, over: connection)
          readRecord(from: connection) { [weak self] peerRecord in
            connection.cancel()
            guard let self, let peerRecord, peerRecord.deviceID != localIdentity.deviceID
            else { return }
            onDiscovered(peerRecord)
          }
        case .failed, .cancelled:
          connection.cancel()
        default:
          break
        }
      }

      connection.start(queue: queue)
    }

    private func makeLocalRecord() -> RappCloudDeviceRecord {
      RappCloudDeviceRecord(
        deviceID: localIdentity.deviceID,
        deviceName: localIdentity.deviceName,
        modelName: localIdentity.modelName,
        role: localRole,
        staticPublicKey: localIdentity.publicKeyData,
        rendezvousToken: RappSameAccountPairBuilder.deriveRendezvousToken(
          publicKeyA: localIdentity.publicKeyData,
          publicKeyB: localIdentity.publicKeyData
        ),
        updatedAt: Date()
      )
    }

    private func sendRecord(_ record: RappCloudDeviceRecord, over connection: NWConnection) {
      guard let json = try? JSONEncoder().encode(record) else { return }
      var payload = Data()
      var length = UInt32(json.count).bigEndian
      payload.append(Data(bytes: &length, count: Constants.lengthHeaderByteCount))
      payload.append(json)
      connection.send(
        content: payload,
        completion: .contentProcessed { _ in
          // Transmission processed
        })
    }

    private func readRecord(
      from connection: NWConnection,
      completion: @escaping @Sendable (RappCloudDeviceRecord?) -> Void
    ) {
      connection.receive(
        minimumIncompleteLength: Constants.lengthHeaderByteCount,
        maximumLength: Constants.lengthHeaderByteCount
      ) { headerData, _, _, error in
        guard error == nil, let headerData, headerData.count == Constants.lengthHeaderByteCount
        else {
          completion(nil)
          return
        }
        let length = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard length > 0, length <= Constants.maxPayloadByteCount else {
          completion(nil)
          return
        }
        connection.receive(
          minimumIncompleteLength: Int(length),
          maximumLength: Int(length)
        ) { bodyData, _, _, _ in
          guard let bodyData, bodyData.count == Int(length) else {
            completion(nil)
            return
          }
          let record = try? JSONDecoder().decode(RappCloudDeviceRecord.self, from: bodyData)
          completion(record)
        }
      }
    }
  }

#endif
