// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import AppKit
  import CardCore
  import RappEngine
  import SwiftUI

  internal struct RemotePairingCodeSection: View {
    private enum Layout {
      static let codeCornerRadius: CGFloat = 12
      static let codeHorizontalPadding: CGFloat = 24
      static let codeVerticalPadding: CGFloat = 16
      static let displayFontSize: CGFloat = 34
      static let trackingSpacing: CGFloat = 3
      static let strokeOpacity: Double = 0.3
      static let strokeLineWidth: CGFloat = 1.5
      static let codeSpacing: CGFloat = 12
      static let copyResetDelayNanoseconds: UInt64 = 2_000_000_000
      static let rowSpacing: CGFloat = 6
      static let statusBadgeSpacing: CGFloat = 4
    }

    @ObservedObject internal var model: RappPairingModel
    @State private var copied = false

    internal var body: some View {
      Section {
        VStack(spacing: Layout.codeSpacing) {
          if case .offer(let code) = model.phase {
            codeCard(code)
            copyCodeButton(code)
          } else if case .connecting = model.phase {
            HStack(spacing: Layout.statusBadgeSpacing) {
              ProgressView()
                .controlSize(.small)
              Text(String(localized: "Connecting..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, Layout.rowSpacing)
          } else {
            HStack(spacing: Layout.statusBadgeSpacing) {
              ProgressView()
                .controlSize(.small)
              Text("Valmistellaan pariliitoskoodia…")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, Layout.rowSpacing)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.rowSpacing)
      } header: {
        Text("Pariliitoskoodi")
      } footer: {
        Text("Syötä tämä koodi puhelimessa liittääksesi sen tähän Maciin.")
      }
    }

    private func codeCard(_ code: String) -> some View {
      Text(code)
        .font(.system(size: Layout.displayFontSize, weight: .bold, design: .monospaced))
        .tracking(Layout.trackingSpacing)
        .padding(.horizontal, Layout.codeHorizontalPadding)
        .padding(.vertical, Layout.codeVerticalPadding)
        .background(
          RoundedRectangle(cornerRadius: Layout.codeCornerRadius)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
              RoundedRectangle(cornerRadius: Layout.codeCornerRadius)
                .stroke(
                  Color.accentColor.opacity(Layout.strokeOpacity),
                  lineWidth: Layout.strokeLineWidth
                )
            )
        )
        .accessibilityIdentifier("pairingCode")
        .accessibilityLabel(code)
    }

    private func copyCodeButton(_ code: String) -> some View {
      Button {
        copyToClipboard(RappPairingCode.normalize(code))
      } label: {
        Label(
          copied ? String(localized: "Code copied") : String(localized: "Copy Code"),
          systemImage: copied ? "checkmark" : "doc.on.doc"
        )
      }
      .buttonStyle(.bordered)
      .controlSize(.regular)
    }

    private func copyToClipboard(_ text: String) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      copied = true
      Task {
        try? await Task.sleep(nanoseconds: Layout.copyResetDelayNanoseconds)
        copied = false
      }
    }
  }

#endif
