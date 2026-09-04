// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import RappEngine
  import SwiftUI

  /// The Settings pane for managing paired devices and automatic connections.
  internal struct RemotePairingSettingsView: View {
    private enum Layout {
      static let rowSpacing: CGFloat = 6
      static let refreshIntervalSeconds: TimeInterval = 3
    }

    private struct DisplayedDevice {
      let identifier: String
      let name: String
      let modelName: String?
      let isPreferred: Bool
      let isOnline: Bool
      let isConnected: Bool
      let onDelete: () -> Void
      let onSetPreferred: () -> Void
    }

    @AppStorage("fi.refineid.preferredRemoteDeviceID")
    private var preferredDeviceID: String = ""

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

    private var displayedDevices: [DisplayedDevice] {
      let validRemoteDevices = remoteDevices.filter { device in
        device.role == .holder && !device.modelName.lowercased().contains("mac")
      }

      let validExtraPairs = model.pairs.filter { pair in
        guard pair.role == .requester else { return false }
        let pairName = RappPairNames.name(forPairID: pair.pairID) ?? ""
        if pairName.lowercased().contains("mac") { return false }
        return !validRemoteDevices.contains { remote in
          remote.deviceName.caseInsensitiveCompare(pairName) == .orderedSame
        }
      }

      let totalCount = validRemoteDevices.count + validExtraPairs.count
      let effectivePreferredID =
        preferredDeviceID.isEmpty && totalCount == 1
        ? (validRemoteDevices.first?.deviceID.uuidString
          ?? validExtraPairs.first?.pairID.base64EncodedString() ?? "")
        : preferredDeviceID

      let localPublicKey = RappAutoPairingService.shared.localIdentity?.publicKeyData

      var list: [DisplayedDevice] = []

      for device in validRemoteDevices {
        let idStr = device.deviceID.uuidString
        let isPreferred = idStr == effectivePreferredID
        let isOnline =
          RappAutoPairingService.shared.isDeviceOnline(
            deviceID: device.deviceID,
            deviceName: device.deviceName
          ) || (isPreferred && PersistentTokenRegistry.shared.holderIsAdvertising)
        let isConnected =
          isOnline && PersistentTokenRegistry.shared.holderIsAdvertising
          && PersistentTokenRegistry.shared.certificateDER != nil

        let derivedPairID: Data?
        if let localPublicKey {
          derivedPairID = RappSameAccountPairBuilder.derivePairIdentifier(
            publicKeyA: localPublicKey,
            publicKeyB: device.staticPublicKey
          )
        } else {
          derivedPairID = nil
        }

        list.append(
          DisplayedDevice(
            identifier: idStr,
            name: device.deviceName,
            modelName: device.modelName,
            isPreferred: isPreferred,
            isOnline: isOnline,
            isConnected: isConnected,
            onDelete: {
              if isPreferred { preferredDeviceID = "" }
              RappAutoPairingService.shared.removeRemoteDevice(deviceID: device.deviceID)
            },
            onSetPreferred: {
              preferredDeviceID = idStr
              if let derivedPairID {
                model.select(pairID: derivedPairID)
              }
              PersistentTokenRegistry.shared.restartWatchingPresence()
            }
          )
        )
      }

      for pair in validExtraPairs {
        let idStr = pair.pairID.base64EncodedString()
        let pairName = RappPairNames.name(forPairID: pair.pairID) ?? String(localized: "Device")
        let isPreferred =
          idStr == effectivePreferredID
          || (model.selectedPairID == pair.pairID)
        let isOnline =
          RappAutoPairingService.shared.isDeviceOnline(
            deviceID: nil,
            deviceName: pairName
          ) || (isPreferred && PersistentTokenRegistry.shared.holderIsAdvertising)
        let isConnected =
          isOnline && PersistentTokenRegistry.shared.holderIsAdvertising
          && PersistentTokenRegistry.shared.certificateDER != nil

        list.append(
          DisplayedDevice(
            identifier: idStr,
            name: pairName,
            modelName: nil,
            isPreferred: isPreferred,
            isOnline: isOnline,
            isConnected: isConnected,
            onDelete: {
              if isPreferred { preferredDeviceID = "" }
              model.revoke(pairID: pair.pairID)
            },
            onSetPreferred: {
              preferredDeviceID = idStr
              model.select(pairID: pair.pairID)
              PersistentTokenRegistry.shared.restartWatchingPresence()
            }
          )
        )
      }

      return list.sorted { lhs, rhs in
        if lhs.isPreferred != rhs.isPreferred {
          return lhs.isPreferred && !rhs.isPreferred
        }
        if lhs.isConnected != rhs.isConnected {
          return lhs.isConnected && !rhs.isConnected
        }
        if lhs.isOnline != rhs.isOnline {
          return lhs.isOnline && !rhs.isOnline
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
    }

    private var remoteDevicesSection: some View {
      let devices = displayedDevices
      return Section {
        if devices.isEmpty {
          Text("Ei liitettyjä laitteita")
            .foregroundStyle(.secondary)
        } else {
          ForEach(devices, id: \.identifier) { device in
            RemoteDeviceRow(
              name: device.name,
              modelName: device.modelName,
              isOnline: device.isOnline,
              isConnected: device.isConnected,
              onDelete: device.onDelete
            )
          }
        }
      } header: {
        Text("Etälaitteet")
      } footer: {
        if !devices.isEmpty {
          HStack {
            Spacer()
            Button("Poista kaikki etälaitteet", role: .destructive) {
              preferredDeviceID = ""
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

    private func reload() {
      model.refresh()
      remoteDevices = RappAutoPairingService.shared.remoteDevices
    }
  }

#endif
