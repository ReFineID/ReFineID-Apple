// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import SwiftUI

  internal struct RemoteDeviceRow: View {
    private enum Layout {
      static let rowSpacing: CGFloat = 8
      static let textVerticalSpacing: CGFloat = 2
      static let titleSpacing: CGFloat = 6
      static let statusBadgeSpacing: CGFloat = 4
      static let statusIndicatorSize: CGFloat = 6
      static let badgeTrailingPadding: CGFloat = 4
    }

    internal let name: String
    internal let modelName: String?
    internal let isPreferred: Bool
    internal let isOnline: Bool
    internal let isConnected: Bool
    internal let onDelete: () -> Void
    internal let onSetPreferred: () -> Void

    internal var body: some View {
      HStack(spacing: Layout.rowSpacing) {
        deviceInfo
        Spacer()
        statusBadge(isOnline: isOnline, isConnected: isConnected)
          .padding(.trailing, Layout.badgeTrailingPadding)
        actionButtons
      }
      .contextMenu {
        contextMenuButtons
      }
    }

    private var deviceInfo: some View {
      VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
        HStack(spacing: Layout.titleSpacing) {
          Text(name)
            .font(.body.weight(.medium))
          if isPreferred {
            Image(systemName: "star.fill")
              .font(.caption)
              .foregroundStyle(.yellow)
              .accessibilityLabel(Text("Ensisijainen laite"))
              .help("Ensisijainen laite")
          }
        }
        if let sub = subtitle(modelName: modelName) {
          Text(sub)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }

    private var actionButtons: some View {
      Group {
        if !isPreferred {
          Button {
            onSetPreferred()
          } label: {
            Image(systemName: "star")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityLabel(Text("Aseta ensisijaiseksi"))
          }
          .buttonStyle(.borderless)
          .help("Aseta ensisijaiseksi")
        }
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
    }

    private var contextMenuButtons: some View {
      Group {
        if !isPreferred {
          Button {
            onSetPreferred()
          } label: {
            Label("Aseta ensisijaiseksi", systemImage: "star")
          }
        }
        Button("Poista laite", role: .destructive) {
          onDelete()
        }
      }
    }

    private func subtitle(modelName: String?) -> String? {
      guard let modelName, !modelName.isEmpty,
        modelName != "Mac", modelName != "Apple"
      else {
        return nil
      }
      return modelName
    }

    @ViewBuilder
    private func statusBadge(isOnline: Bool, isConnected: Bool) -> some View {
      if isConnected {
        HStack(spacing: Layout.statusBadgeSpacing) {
          Circle()
            .fill(Color.green)
            .frame(width: Layout.statusIndicatorSize, height: Layout.statusIndicatorSize)
          Text("Yhdistetty")
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
