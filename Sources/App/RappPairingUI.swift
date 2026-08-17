// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CoreImage
import Foundation
import Observation
import ReFineIDRapp
import SwiftUI

#if os(iOS)
  import UIKit
  import VisionKit
#elseif os(macOS)
  import AppKit
#endif

private enum RappApplePeerProfile {
  static let name = "apple-peer-v1"
  static let candidateID = "apple-peer-v1.nearby"

  /// Deterministic CBOR for an empty map.
  ///
  /// Apple peer discovery currently needs no public parameter beyond
  /// its bound profile and candidate ID.
  private static let emptyMapInitialByte: UInt8 = 0b1010_0000
  static let candidateParameters = Data([emptyMapInitialByte])

  /// Only profiles implemented end to end by the current phone executor.
  static let supportedCredentialProfiles = [
    "fi.eid.card-status.v1",
    "fi.eid.authentication.v1",
    "fi.eid.document-signing.v1",
  ]

  static func isSupported(_ profile: String) -> Bool {
    supportedCredentialProfiles.contains(profile)
  }

  static func label(for profile: String) -> String {
    switch profile {
    case "fi.eid.card-status.v1": String(localized: "Card status")
    case "fi.eid.authentication.v1": String(localized: "Browser authentication")
    case "fi.eid.document-signing.v1": String(localized: "Document signing")
    case "fi.eid.activation.v1": String(localized: "Card activation")
    case "fi.eid.pin-management.v1": String(localized: "PIN management")
    default: String(localized: "Unknown access")
    }
  }
}

@MainActor
@Observable
internal final class RappPairingModel {
  internal enum Phase: Equatable {
    case idle
    case offer(String)
    case scanning
    case connecting
    case review(RappPairingCoordinator.Peer)
    case paired(RappPairingCoordinator.PairSummary)
    case failed(String)
  }

  private enum Policy {
    /// RAPP 0.1 OFFER_TTL_MAX.
    static let offerLifetimeMilliseconds: UInt64 = 180_000
  }

  /// The in-protocol name the reviewing peer sees for this requester.
  private static var requesterDisplayName: String {
    #if os(macOS)
      Host.current().localizedName ?? String(localized: "Mac")
    #else
      UIDevice.current.name
    #endif
  }

  /// The in-protocol platform name for this requester.
  private static var requesterPlatform: String {
    #if os(macOS)
      "macOS"
    #else
      "iOS"
    #endif
  }

  internal private(set) var phase = Phase.idle
  internal private(set) var pairs: [RappPairingCoordinator.PairSummary] = []
  internal private(set) var selectedPairID: Data?

  private var relay: PersistentRelaySession?
  private var streamRelay: StreamRelaySession?
  private var streamEverConnected = false
  private var relayGeneration: UUID?
  private var relayRouter: RappRelayEventRouter<PersistentRelayEvent>?
  private var streamRouter: RappRelayEventRouter<StreamRelayEvent>?
  private var coordinator: RappPairingCoordinator?
  private var eventTask: Task<Void, Never>?
  private var reviewedPeerName: String?

  /// A pairing is the live connection, so the list mirrors the process's
  /// one live pairing on the proxy; the requester side lists the pair it
  /// completed for this model's lifetime.
  internal func refresh() {
    #if os(iOS)
      if let live = PhonePersistentTokenRelay.shared.livePairing {
        pairs = [live.summary]
        selectedPairID = live.summary.pairID
      } else if case .paired = phase {
        // The requester-side pair set at completion stays listed.
      } else {
        pairs = []
        selectedPairID = nil
      }
    #endif
  }

  internal func createOffer() {
    resetAttempt()
    let relay = makeRelay(role: .host)
    let transport = makeTransport(relay: relay)
    do {
      let coordinator = try RappPairingCoordinator.requester(
        profiles: RappApplePeerProfile.supportedCredentialProfiles,
        candidates: [
          .init(
            profile: RappApplePeerProfile.name,
            candidateID: RappApplePeerProfile.candidateID,
            parametersCBOR: RappApplePeerProfile.candidateParameters
          )
        ],
        selectedCandidateID: RappApplePeerProfile.candidateID,
        offerLifetimeMilliseconds: Policy.offerLifetimeMilliseconds,
        displayName: Self.requesterDisplayName,
        platform: Self.requesterPlatform,
        transport: transport
      )
      install(coordinator: coordinator, relay: relay)
      Task { [weak self] in
        await coordinator.publishOffer()
        guard let self, self.coordinator === coordinator, !isFinished
        else { return }
        relay.start()
      }
    } catch {
      fail(String(localized: "Pairing could not be started"))
    }
  }

  #if os(iOS)
    internal func scanOffer() {
      resetAttempt()
      guard DataScannerViewController.isSupported,
        DataScannerViewController.isAvailable
      else {
        fail(String(localized: "The camera cannot scan pairing codes right now"))
        return
      }
      phase = .scanning
    }

    internal func acceptScannedOffer(_ uri: String) {
      guard phase == .scanning else { return }
      phase = .connecting
      do {
        let candidates = try RappScannedOffer.candidates(scannedOfferURI: uri)
        if let applePeer = candidates.first(where: { candidate in
          candidate.profile == RappApplePeerProfile.name
        }) {
          try startApplePeerPairing(uri: uri, candidateID: applePeer.candidateID)
        } else if let stream = candidates.first(where: { candidate in
          candidate.profile == rappStreamProfileName()
            && !candidate.streamEndpoints.isEmpty
        }) {
          try startStreamPairing(uri: uri, candidate: stream)
        } else {
          fail(String(localized: "The pairing code is invalid or expired"))
        }
      } catch {
        fail(String(localized: "The pairing code is invalid or expired"))
      }
    }

    private func startApplePeerPairing(uri: String, candidateID: String) throws {
      let relay = makeRelay(role: .cardHolder)
      let transport = makeTransport(relay: relay)
      let coordinator = try RappPairingCoordinator.proxy(
        scannedOfferURI: uri,
        selectedCandidateID: candidateID,
        displayName: UIDevice.current.name,
        platform: "iOS",
        transport: transport
      )
      install(coordinator: coordinator, relay: relay)
      relay.start()
    }

    /// Dials the stream candidate's listener endpoints with the pairing
    /// preamble and runs the pairing ceremony over that connection.
    private func startStreamPairing(
      uri: String,
      candidate: RappScannedOffer.Candidate
    ) throws {
      let generation = UUID()
      relayGeneration = generation
      streamEverConnected = false
      let router = RappRelayEventRouter<StreamRelayEvent> { [weak self] event in
        Task { @MainActor in
          self?.receiveStream(event, generation: generation)
        }
      }
      streamRouter = router
      let stream = StreamRelaySession(
        endpointLiterals: candidate.streamEndpoints,
        preamble: rappStreamPairingPreamble()
      ) { event in
        router.route(event)
      }
      let transport = RappClosureFrameTransport(
        sender: { [weak stream] frame in
          guard let stream else {
            throw StreamRelayTransportError.notConnected
          }
          try await stream.send(frame)
        },
        closer: { [weak stream] in stream?.cancel() }
      )
      let coordinator = try RappPairingCoordinator.proxy(
        scannedOfferURI: uri,
        selectedCandidateID: candidate.candidateID,
        displayName: UIDevice.current.name,
        platform: "iOS",
        transport: transport
      )
      self.coordinator = coordinator
      streamRelay = stream
      eventTask = Task { [weak self] in
        for await event in coordinator.events {
          self?.receive(event, from: coordinator)
        }
      }
      stream.start()
    }

    private func receiveStream(_ event: StreamRelayEvent, generation: UUID) {
      guard generation == relayGeneration else { return }
      guard let coordinator else { return }
      switch event {
      case .connected:
        streamEverConnected = true
        Task { await coordinator.transportConnected() }
      case .frame(let frame):
        Task { await coordinator.receive(frame) }
      case .closed:
        guard !isFinished else {
          finishAttempt()
          return
        }
        // A dial that never connected leaves the coordinator in its offer
        // state, where transport closure is not an event.
        guard streamEverConnected else {
          fail(String(localized: "Pairing ended before it was completed"))
          return
        }
        Task { await coordinator.transportClosed() }
      }
    }
  #endif

  internal func requestedProfiles(
    for peer: RappPairingCoordinator.Peer
  ) -> [String] {
    peer.requestedProfiles ?? RappApplePeerProfile.supportedCredentialProfiles
  }

  internal func profileLabel(_ profile: String) -> String {
    RappApplePeerProfile.label(for: profile)
  }

  internal func profileIsSupported(_ profile: String) -> Bool {
    RappApplePeerProfile.isSupported(profile)
  }

  internal func approvePeer() {
    guard case .review(let peer) = phase else { return }
    confirmPeer(peer)
  }

  /// Grants exactly the requested, supported profiles and proceeds to store
  /// the pairing.
  ///
  /// Used by the requester's manual confirmation and by the proxy's automatic
  /// confirmation.
  private func confirmPeer(_ peer: RappPairingCoordinator.Peer) {
    guard let coordinator else { return }
    let grantSet = requestedProfiles(for: peer).filter(
      RappApplePeerProfile.isSupported)
    guard !grantSet.isEmpty else {
      denyPeer()
      return
    }
    phase = .connecting
    Task { await coordinator.approve(grantedProfiles: grantSet) }
  }

  internal func denyPeer() {
    guard let coordinator else {
      cancel()
      return
    }
    phase = .failed(String(localized: "Pairing was denied"))
    Task { [weak self] in
      await coordinator.deny()
      self?.finishAttempt()
    }
  }

  /// Ends the pairing: the live connection closes and both peers drop it.
  internal func removePairing() {
    #if os(iOS)
      PhonePersistentTokenRelay.shared.endLivePairing()
    #endif
    pairs = []
    selectedPairID = nil
    cancel()
  }

  /// The paired device's reviewed name, or its role label.
  internal func displayName(
    for pair: RappPairingCoordinator.PairSummary
  ) -> String {
    #if os(iOS)
      if let live = PhonePersistentTokenRelay.shared.livePairing,
        live.summary.pairID == pair.pairID,
        let name = live.peerName
      {
        return name
      }
    #endif
    return reviewedPeerName ?? pair.remotePlatformLabel
  }

  internal func cancel() {
    let coordinator = coordinator
    relay?.cancel()
    streamRelay?.cancel()
    finishAttempt()
    phase = .idle
    Task { await coordinator?.close() }
  }

  private func makeRelay(role: PersistentRelayRole) -> PersistentRelaySession {
    let generation = UUID()
    relayGeneration = generation
    let displayName: String
    switch role {
    case .host:
      #if os(macOS)
        displayName = String(localized: "ReFineID Mac")
      #else
        displayName = String(localized: "ReFineID iPad")
      #endif
    case .cardHolder:
      displayName = String(localized: "ReFineID iPhone")
    }
    let router = RappRelayEventRouter<PersistentRelayEvent> { [weak self] event in
      Task { @MainActor in self?.receive(event, generation: generation) }
    }
    relayRouter = router
    return PersistentRelaySession(
      role: role,
      displayName: displayName
    ) { event in
      router.route(event)
    }
  }

  private func makeTransport(
    relay: PersistentRelaySession
  ) -> RappClosureFrameTransport {
    RappClosureFrameTransport(
      sender: { [weak relay] frame in
        guard let relay else {
          throw PersistentRelayTransportError.disconnected
        }
        try relay.send(frame)
      },
      closer: { [weak relay] in relay?.cancel() }
    )
  }

  private func install(
    coordinator: RappPairingCoordinator,
    relay: PersistentRelaySession
  ) {
    self.coordinator = coordinator
    self.relay = relay
    eventTask = Task { [weak self] in
      for await event in coordinator.events {
        self?.receive(event, from: coordinator)
      }
    }
  }

  private func receive(
    _ event: PersistentRelayEvent,
    generation: UUID
  ) {
    guard generation == relayGeneration else { return }
    guard let coordinator else { return }
    switch event {
    case .connected:
      Task { await coordinator.transportConnected() }
    case .frame(let frame):
      Task { await coordinator.receive(frame) }
    case .closed:
      guard !isFinished else {
        finishAttempt()
        return
      }
      Task { await coordinator.transportClosed() }
    }
  }

  private func receive(
    _ event: RappPairingCoordinator.Event,
    from coordinator: RappPairingCoordinator
  ) {
    guard self.coordinator === coordinator else { return }
    switch event {
    case .offerReady(let uri):
      phase = .offer(uri)
    case .offerRestored(let uri):
      restoreRequesterOffer(uri, coordinator: coordinator)
    case .reviewPeer(let peer):
      reviewedPeerName = peer.displayName
      // The scan of the offer QR, carrying its 256-bit bearer secret, is the
      // human consent that authorizes this pairing and its public reads. A
      // peer that lists requested profiles is the requester, so this device is
      // the proxy and confirms automatically with the requested grant set. The
      // requester still confirms the scanned proxy explicitly.
      if peer.requestedProfiles != nil {
        confirmPeer(peer)
      } else {
        phase = .review(peer)
      }
    case .paired(let pair):
      selectedPairID = pair.pairID
      pairs = [pair]
      phase = .paired(pair)
      // The proxy hands its live channel to the process-wide holder. The
      // requester-side channel lives only as long as this model, because a
      // process-wide requester holder does not exist yet.
      #if os(iOS)
        if pair.role == .proxy {
          handOver(pair, from: coordinator)
        }
      #endif
    case .closed:
      guard !isFinished else { return }
      fail(String(localized: "Pairing ended before it was completed"))
    }
  }

  #if os(iOS)
    /// Hands the completed pairing's live channel to the process-wide
    /// proxy holder: relay events re-route there, and the model keeps no
    /// claim on the connection.
    private func handOver(
      _ pair: RappPairingCoordinator.PairSummary,
      from coordinator: RappPairingCoordinator?
    ) {
      let shared = PhonePersistentTokenRelay.shared
      shared.beginAdoption()
      routeAdoptedEventsToHolder()
      let channel: AnyObject? =
        streamRelay.map { $0 as AnyObject } ?? relay.map { $0 as AnyObject }
      let peerName = reviewedPeerName
      streamRelay = nil
      relay = nil
      relayGeneration = nil
      streamRouter = nil
      relayRouter = nil
      eventTask?.cancel()
      eventTask = nil
      self.coordinator = nil
      Task { @MainActor [weak self] in
        guard let handover = await coordinator?.continueEstablished() else {
          shared.abandonAdoption()
          return
        }
        shared.completeAdoption(
          pairing: handover.pairing,
          transport: handover.transport,
          summary: pair,
          peerName: peerName,
          retaining: channel
        )
        self?.refresh()
      }
    }

    /// Re-points both relay routers at the process-wide holder.
    private func routeAdoptedEventsToHolder() {
      streamRouter?.install { event in
        Task { @MainActor in
          switch event {
          case .connected:
            break
          case .frame(let frame):
            Self.forwardAdopted(frame: frame)
          case .closed:
            Self.forwardAdoptedClose()
          }
        }
      }
      relayRouter?.install { event in
        Task { @MainActor in
          switch event {
          case .connected:
            break
          case .frame(let frame):
            Self.forwardAdopted(frame: frame)
          case .closed:
            Self.forwardAdoptedClose()
          }
        }
      }
    }

    private static func forwardAdopted(frame: Data) {
      PhonePersistentTokenRelay.shared.receiveAdoptedFrame(frame)
    }

    private static func forwardAdoptedClose() {
      PhonePersistentTokenRelay.shared.adoptedTransportClosed()
    }
  #endif

  private func restoreRequesterOffer(
    _ uri: String,
    coordinator: RappPairingCoordinator
  ) {
    phase = .offer(uri)
    relay?.cancel()
    let replacement = makeRelay(role: .host)
    let replacementTransport = makeTransport(relay: replacement)
    relay = replacement
    Task { @MainActor [weak self] in
      guard await coordinator.replaceTransport(replacementTransport),
        let self,
        self.coordinator === coordinator,
        !isFinished
      else {
        self?.fail(String(localized: "Pairing could not be started"))
        return
      }
      replacement.start()
    }
  }

  private var isFinished: Bool {
    switch phase {
    case .paired, .failed: true
    case .idle, .offer, .scanning, .connecting, .review: false
    }
  }

  private func fail(_ message: String) {
    let coordinator = coordinator
    phase = .failed(message)
    relay?.cancel()
    streamRelay?.cancel()
    finishAttempt()
    Task { await coordinator?.close() }
  }

  private func finishAttempt() {
    relay = nil
    streamRelay = nil
    relayGeneration = nil
    relayRouter = nil
    streamRouter = nil
    coordinator = nil
    eventTask?.cancel()
    eventTask = nil
  }

  private func resetAttempt() {
    let coordinator = coordinator
    relay?.cancel()
    streamRelay?.cancel()
    finishAttempt()
    phase = .idle
    Task { await coordinator?.close() }
  }

}

internal struct RappPairingButton: View {
  @Binding internal var isPresented: Bool
  @State private var hasSelectedPair = false

  internal var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: hasSelectedPair ? "link" : "link.badge.plus")
        .contentTransition(.symbolEffect(.replace))
    }
    .accessibilityLabel("Remote Card")
    .accessibilityValue(
      hasSelectedPair ? "Paired device selected" : "No paired device selected"
    )
    .task(id: isPresented) {
      #if os(iOS)
        hasSelectedPair = PhonePersistentTokenRelay.shared.livePairing != nil
      #else
        hasSelectedPair = false
      #endif
    }
  }
}

internal struct RappPairingView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model = RappPairingModel()

  internal var body: some View {
    NavigationStack {
      Form {
        pairedDevices
        pairingAction
        pairingProgress
      }
      .navigationTitle("Remote Card")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
    .onAppear { model.refresh() }
    .onDisappear { model.cancel() }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 520)
    #endif
  }

  @ViewBuilder private var pairedDevices: some View {
    if !model.pairs.isEmpty {
      Section("Paired devices") {
        ForEach(model.pairs, id: \.pairID) { pair in
          HStack {
            Label(
              model.displayName(for: pair),
              systemImage: pair.remotePlatformSymbol
            )
            Spacer()
            if model.selectedPairID == pair.pairID {
              Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Selected")
            }
          }
          Button("Remove this pairing", role: .destructive) {
            model.removePairing()
          }
          .accessibilityIdentifier("removePairedDevice")
        }
      }
    }
  }

  /// One connection at a time: pairing is offered only while no
  /// paired device exists.
  @ViewBuilder private var pairingAction: some View {
    if model.pairs.isEmpty {
      Section {
        #if os(macOS)
          Button("Pair a phone", systemImage: "qrcode") {
            model.createOffer()
          }
        #else
          // A device with an antenna holds the card and scans; a device
          // without one requests and shows the code to scan.
          if UIDevice.current.userInterfaceIdiom == .pad {
            Button("Pair a phone", systemImage: "qrcode") {
              model.createOffer()
            }
          } else {
            Button("Scan pairing code", systemImage: "qrcode.viewfinder") {
              model.scanOffer()
            }
          }
        #endif
      }
    }
  }

  @ViewBuilder private var pairingProgress: some View {
    switch model.phase {
    case .idle:
      EmptyView()
    case .offer(let uri):
      Section("Scan with ReFineID on the phone") {
        if let image = RappPairingCode.image(uri) {
          image
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 280, maxHeight: 280)
            .accessibilityLabel("Pairing QR code")
        }
        ProgressView("Waiting for the phone")
      }
    case .scanning:
      #if os(iOS)
        Section("Scan the code shown on the other device") {
          RappOfferScanner { model.acceptScannedOffer($0) }
            .frame(minHeight: 320)
            .clipShape(.rect(cornerRadius: 16))
            .accessibilityLabel("Pairing code scanner")
        }
      #endif
    case .connecting:
      Section { ProgressView("Establishing a secure connection") }
    case .review(let peer):
      Section("Confirm the other device") {
        LabeledContent("Device", value: peer.displayName)
        LabeledContent("Platform", value: peer.platform)
        Button("Allow this device") { model.approvePeer() }
          .buttonStyle(.borderedProminent)
        Button("Deny", role: .destructive) { model.denyPeer() }
      }
    case .paired(let pair):
      Section {
        Label("Secure pairing established", systemImage: "checkmark.shield")
          .foregroundStyle(.green)
        Text(pair.remotePlatformLabel)
      }
    case .failed(let message):
      Section {
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      }
    }
  }
}

extension RappPairingCoordinator.PairSummary {
  fileprivate var remotePlatformLabel: String {
    switch role {
    case .requester: String(localized: "Card-holding device")
    case .proxy: String(localized: "Requesting device")
    }
  }

  fileprivate var remotePlatformSymbol: String {
    switch role {
    case .requester: "iphone"
    case .proxy: "desktopcomputer"
    }
  }
}

private enum RappPairingCode {
  static func image(_ value: String) -> Image? {
    let filter = CIFilter(name: "CIQRCodeGenerator")
    filter?.setValue(Data(value.utf8), forKey: "inputMessage")
    filter?.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter?.outputImage else { return nil }
    #if os(macOS)
      let representation = NSCIImageRep(ciImage: output)
      let image = NSImage(size: representation.size)
      image.addRepresentation(representation)
      return Image(nsImage: image)
    #else
      let context = CIContext(options: nil)
      guard let cgImage = context.createCGImage(output, from: output.extent)
      else { return nil }
      return Image(uiImage: UIImage(cgImage: cgImage))
    #endif
  }
}

#if os(iOS)
  private struct RappOfferScanner: UIViewControllerRepresentable {
    let onScan: @MainActor @Sendable (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
      let scanner = DataScannerViewController(
        recognizedDataTypes: [.barcode(symbologies: [.qr])],
        qualityLevel: .balanced,
        recognizesMultipleItems: false,
        isHighFrameRateTrackingEnabled: false,
        isPinchToZoomEnabled: true,
        isGuidanceEnabled: true,
        isHighlightingEnabled: true
      )
      scanner.delegate = context.coordinator
      DispatchQueue.main.async { try? scanner.startScanning() }
      return scanner
    }

    func updateUIViewController(
      _: DataScannerViewController,
      context _: Context
    ) {}

    static func dismantleUIViewController(
      _ scanner: DataScannerViewController,
      coordinator _: Coordinator
    ) {
      scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
      private let onScan: @MainActor @Sendable (String) -> Void
      private var accepted = false

      init(onScan: @escaping @MainActor @Sendable (String) -> Void) {
        self.onScan = onScan
      }

      func dataScanner(
        _: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems _: [RecognizedItem]
      ) {
        guard !accepted else { return }
        for item in addedItems {
          guard case .barcode(let barcode) = item,
            let value = barcode.payloadStringValue
          else { continue }
          accepted = true
          Task { @MainActor [onScan] in onScan(value) }
          return
        }
      }
    }
  }
#endif
