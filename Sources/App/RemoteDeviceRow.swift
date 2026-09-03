// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import SwiftUI

  internal struct RemoteDeviceRow: View {
    private enum Layout {
      static let deviceIconWidth: CGFloat = 24
      static let rowSpacing: CGFloat = 6
      static let textVerticalSpacing: CGFloat = 2
      static let statusBadgeSpacing: CGFloat = 4
      static let statusIndicatorSize: CGFloat = 6
      static let badgeTrailingPadding: CGFloat = 4
    }

    internal let deviceID: UUID?
    internal let name: String
    internal let isHolder: Bool
    internal let modelName: String?
    internal let onDelete: () -> Void

    internal var body: some View {
      let isOnline =
        RappAutoPairingService.shared.isDeviceOnline(
          deviceID: deviceID,
          deviceName: name
        ) || (isHolder && PersistentTokenRegistry.shared.holderIsAdvertising)
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
  }

#endif
