// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import SwiftUI

  /// The Settings pane for managing paired devices and automatic connections.
  internal struct RemotePairingSettingsView: View {
    private enum Layout {
      static let deviceIconWidth: CGFloat = 24
      static let rowSpacing: CGFloat = 6
    }

    @StateObject private var model = RappPairingModel()
    @State private var remoteDevices: [RappCloudDeviceRecord] = []

    internal var body: some View {
      Form {
        devicesSection
      }
      .formStyle(.grouped)
      .onAppear {
        reload()
        RappAutoPairingService.shared.reconcile()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappAutoPairingService.pairingsDidChangeNotification
        )
      ) { _ in
        reload()
      }
    }

    private var devicesSection: some View {
      Section("Laitteet") {
        if remoteDevices.isEmpty, model.pairs.isEmpty {
          Text("Ei liitettyjä laitteita")
            .foregroundStyle(.secondary)
        } else {
          ForEach(remoteDevices, id: \.deviceID) { device in
            deviceRow(
              name: device.deviceName,
              isHolder: device.role == .holder
            )
          }
          ForEach(extraModelPairs, id: \.pairID) { pair in
            deviceRow(
              name: RappPairNames.name(forPairID: pair.pairID) ?? String(localized: "Device"),
              isHolder: pair.role == .proxy
            )
          }
        }
      }
    }

    private var extraModelPairs: [RappPairingCoordinator.PairSummary] {
      model.pairs.filter { pair in
        !remoteDevices.contains { remote in
          RappPairNames.name(forPairID: pair.pairID) == remote.deviceName
        }
      }
    }

    private func deviceRow(name: String, isHolder: Bool) -> some View {
      HStack(spacing: Layout.rowSpacing) {
        Image(systemName: isHolder ? "iphone" : "ipad")
          .font(.title3)
          .foregroundStyle(.tint)
          .frame(width: Layout.deviceIconWidth)
          .accessibilityHidden(true)
        VStack(alignment: .leading) {
          Text(name)
            .font(.body.weight(.medium))
          Text(isHolder ? "Henkilökortti saatavilla" : "Etälukija")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("Valmis")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.green)
      }
    }

    private func reload() {
      model.refresh()
      remoteDevices = RappAutoPairingService.shared.remoteDevices
    }
  }

#endif
