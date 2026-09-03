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
      static let refreshIntervalSeconds: TimeInterval = 3
      static let retryDelayNanoseconds: UInt64 = 1_000_000_000
    }

    @StateObject private var model = RappPairingModel()
    @State private var remoteDevices: [RappCloudDeviceRecord] = []

    internal var body: some View {
      Form {
        localDeviceSection
        RemotePairingCodeSection(model: model)
        remoteDevicesSection
      }
      .formStyle(.grouped)
      .onAppear {
        reload()
        RappAutoPairingService.shared.reconcile()
        ensureOffer()
      }
      .onDisappear {
        model.cancel()
      }
      .onReceive(model.$phase) { phase in
        switch phase {
        case .paired:
          reload()
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: Layout.retryDelayNanoseconds)
            ensureOffer()
          }

        case .failed:
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: Layout.retryDelayNanoseconds)
            ensureOffer()
          }

        default:
          break
        }
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

    private var localDeviceSection: some View {
      Section {
        HStack(spacing: Layout.rowSpacing) {
          Image(systemName: "laptopcomputer")
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(width: Layout.deviceIconWidth)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
            Text(localDeviceTitle)
              .font(.body.weight(.medium))
            Text("Mac • \(localRoleDescription)")
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

    private var remoteDevicesSection: some View {
      Section {
        if remoteDevices.isEmpty, model.pairs.isEmpty {
          Text("Ei muita liitettyjä laitteita")
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

    private var localDeviceTitle: String {
      Host.current().localizedName ?? String(localized: "Mac")
    }

    private var localRoleDescription: String {
      #if os(macOS)
        "Etälukija"
      #else
        "NFC-kortinlukija"
      #endif
    }

    private func ensureOffer() {
      switch model.phase {
      case .offer, .connecting:
        break

      default:
        model.createOffer()
      }
    }

    private func reload() {
      model.refresh()
      remoteDevices = RappAutoPairingService.shared.remoteDevices
    }
  }

#endif
