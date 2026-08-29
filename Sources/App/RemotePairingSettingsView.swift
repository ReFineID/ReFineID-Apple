// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import SwiftUI

  /// The Settings pane for managing paired devices and automatic connections.
  internal struct RemotePairingSettingsView: View {
    private enum Layout {
      static let deviceIconWidth: CGFloat = 24
      static let rowSpacing: CGFloat = 6
      static let textVerticalSpacing: CGFloat = 2
      static let statusBadgeSpacing: CGFloat = 4
      static let statusIndicatorSize: CGFloat = 6
      static let badgeTrailingPadding: CGFloat = 4
    }

    @StateObject private var model = RappPairingModel()
    @State private var remoteDevices: [RappCloudDeviceRecord] = []

    internal var body: some View {
      Form {
        localDeviceSection
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
    }

    private var localDeviceSection: some View {
      Section {
        HStack(spacing: Layout.rowSpacing) {
          Image(systemName: "laptopcomputer")
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(width: Layout.deviceIconWidth)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
            Text(localDeviceName)
              .font(.body.weight(.medium))
            Text(localDeviceSubtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          HStack(spacing: Layout.statusBadgeSpacing) {
            Circle()
              .fill(Color.green)
              .frame(width: Layout.statusIndicatorSize, height: Layout.statusIndicatorSize)
            Text("Tämä laite")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.green)
          }
          .padding(.trailing, Layout.badgeTrailingPadding)
        }
      } header: {
        Text("Tämä laite")
      }
    }

    private var localDeviceName: String {
      RappAutoPairingService.shared.localIdentity?.deviceName
        ?? Host.current().localizedName
        ?? ProcessInfo.processInfo.hostName
    }

    private var localDeviceSubtitle: String {
      let deviceModel = RappAutoPairingService.shared.localIdentity?.modelName ?? "Mac"
      let isHolder = RappAutoPairingService.shared.localRole == .holder
      let role = isHolder ? "NFC-kortinlukija" : "Etälukija"
      if !deviceModel.isEmpty, deviceModel != "Mac", deviceModel != "Apple" {
        return "\(deviceModel) • \(role)"
      }
      return role
    }

    private var remoteDevicesSection: some View {
      Section {
        if remoteDevices.isEmpty, model.pairs.isEmpty {
          Text("Ei muita liitettyjä laitteita")
            .foregroundStyle(.secondary)
        } else {
          ForEach(remoteDevices, id: \.deviceID) { device in
            deviceRow(
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
            deviceRow(
              deviceID: nil,
              name: RappPairNames.name(forPairID: pair.pairID) ?? String(localized: "Device"),
              isHolder: pair.role == .proxy,
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

    private func deviceRow(
      deviceID: UUID?,
      name: String,
      isHolder: Bool,
      modelName: String?,
      onDelete: @escaping () -> Void
    ) -> some View {
      let isOnline = RappAutoPairingService.shared.isDeviceOnline(
        deviceID: deviceID,
        deviceName: name
      )
      let cardIsReady =
        isHolder
        && (PersistentTokenRegistry.shared.holderIsAdvertising
          || CardPresence.shared.isReaderCardPresent)

      return HStack(spacing: Layout.rowSpacing) {
        Image(systemName: isHolder ? "iphone" : "ipad")
          .font(.title3)
          .foregroundStyle(.tint)
          .frame(width: Layout.deviceIconWidth)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
          Text(name)
            .font(.body.weight(.medium))
          Text(subtitle(modelName: modelName, isHolder: isHolder, cardIsReady: cardIsReady))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        statusBadge(isOnline: isOnline, cardIsReady: cardIsReady)
          .padding(.trailing, Layout.badgeTrailingPadding)
        Button {
          onDelete()
        } label: {
          Image(systemName: "trash")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Poista laite"))
        }
        .buttonStyle(.borderless)
        .help("Poista laite")
      }
      .contextMenu {
        Button("Poista laite", role: .destructive) {
          onDelete()
        }
      }
    }

    private func subtitle(modelName: String?, isHolder: Bool, cardIsReady: Bool) -> String {
      let roleDesc: String
      if isHolder {
        roleDesc = cardIsReady ? "NFC-kortinlukija (Kortti valmiina)" : "NFC-kortinlukija"
      } else {
        roleDesc = "Etälukija"
      }

      if let modelName, !modelName.isEmpty,
        modelName != "Mac", modelName != "Apple",
        modelName != roleDesc
      {
        return "\(modelName) • \(roleDesc)"
      }
      return roleDesc
    }

    @ViewBuilder
    private func statusBadge(isOnline: Bool, cardIsReady: Bool) -> some View {
      if cardIsReady {
        HStack(spacing: Layout.statusBadgeSpacing) {
          Circle()
            .fill(Color.green)
            .frame(width: Layout.statusIndicatorSize, height: Layout.statusIndicatorSize)
          Text("Kortti valmiina")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
        }
      } else if isOnline {
        HStack(spacing: Layout.statusBadgeSpacing) {
          Circle()
            .fill(Color.green)
            .frame(width: Layout.statusIndicatorSize, height: Layout.statusIndicatorSize)
          Text("Linjoilla")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
        }
      } else {
        Text("Ei linjoilla")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }

    private func reload() {
      model.refresh()
      remoteDevices = RappAutoPairingService.shared.remoteDevices
    }
  }

#endif
