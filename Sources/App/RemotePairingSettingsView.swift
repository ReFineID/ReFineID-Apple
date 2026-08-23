// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import SwiftUI

  /// The Settings pane that offers a pairing code, and nothing else.
  internal struct RemotePairingSettingsView: View {
    private enum Layout {
      static let displayFontSize: CGFloat = 38
      static let trackingSpacing: CGFloat = 3
    }

    @StateObject private var model = RappPairingModel()

    internal var body: some View {
      Group {
        if case .offer(let code) = model.phase {
          Text(RappPairingCode.formatted(code))
            .font(.system(size: Layout.displayFontSize, weight: .bold, design: .monospaced))
            .tracking(Layout.trackingSpacing)
            .accessibilityIdentifier("pairingCode")
            .accessibilityLabel(code)
        } else if case .failed(let error) = model.phase {
          Text(error)
            .font(.footnote)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
        } else {
          ProgressView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        model.refresh()
        model.createOffer()
      }
      .onDisappear {
        model.cancel()
      }
      .onReceive(model.$phase) { phase in
        if case .paired = phase {
          model.createOffer()
        }
      }
    }
  }

#endif
