// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import SwiftUI

  /// The Settings pane for managing paired devices and automatic connections.
  internal struct RemotePairingSettingsView: View {
    private enum Layout {
      static let rowSpacing: CGFloat = 6
      static let refreshIntervalSeconds: TimeInterval = 3
    }

    @StateObject private var model = RappPairingModel()
    @State private var remoteDevices: [RappCloudDeviceRecord] = []

    internal var body: some View {
      Form {
        remoteDevicesSection
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
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappPairingModel.pairingsDidChangeNotification
        )
      ) { _ in
        reload()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: NSApplication.didBecomeActiveNotification
        )
      ) { _ in
        reload()
      }
      .onReceive(
        Timer.publish(every: Layout.refreshIntervalSeconds, on: .main, in: .common).autoconnect()
      ) { _ in
        reload()
      }
    }

    private var remoteDevicesSection: some View {
      Section {
        if remoteDevices.isEmpty, model.pairs.isEmpty {
          Text("Ei liitettyjä laitteita")
            .foregroundStyle(.secondary)
        } else {
          ForEach(remoteDevices, id: \.deviceID) { device in
            RemoteDeviceRow(
              deviceID: device.deviceID,
              name: device.deviceName,
              isHolder: device.role == .holder,
              modelName: device.modelName,
              onDelete: {
                RappAutoPairingService.shared.removeRemoteDevice(deviceID: device.deviceID)
              }
            )
          }
          ForEach(extraModelPairs, id: \.pairID) { pair in
            RemoteDeviceRow(
              deviceID: nil,
              name: RappPairNames.name(forPairID: pair.pairID) ?? String(localized: "Device"),
              isHolder: pair.role == .requester,
              modelName: nil,
              onDelete: {
                model.revoke(pairID: pair.pairID)
              }
            )
          }
        }
      } header: {
        Text("Etälaitteet")
      } footer: {
        if !remoteDevices.isEmpty || !model.pairs.isEmpty {
          HStack {
            Spacer()
            Button("Poista kaikki etälaitteet", role: .destructive) {
              RappAutoPairingService.shared.clearAllRemoteDevices()
              model.revokeAll()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)
          }
          .padding(.top, Layout.rowSpacing)
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

    private func reload() {
      model.refresh()
      remoteDevices = RappAutoPairingService.shared.remoteDevices
    }
  }

#endif
