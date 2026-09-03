// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import SwiftUI

  internal struct RemotePairingPromptView: View {
    private enum Layout {
      static let retryDelayNanoseconds: UInt64 = 1_000_000_000
    }

    @StateObject private var model = RappPairingModel()

    internal var body: some View {
      promptText
        .onAppear {
          ensureOffer()
        }
        .onReceive(model.$phase) { phase in
          switch phase {
          case .paired, .failed:
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: Layout.retryDelayNanoseconds)
              ensureOffer()
            }

          default:
            break
          }
        }
    }

    @ViewBuilder private var promptText: some View {
      if case .offer(let code) = model.phase {
        let formattedCode = RappPairingCode.formatted(code)
        Text(String(localized: "Connect phone as reader with code: \(formattedCode)"))
          .textSelection(.enabled)
          .accessibilityIdentifier("pairingPrompt")
      } else if case .connecting = model.phase {
        Text(String(localized: "Connecting..."))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("pairingPrompt")
      } else {
        Text(String(localized: "Preparing pairing code..."))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("pairingPrompt")
      }
    }

    private func ensureOffer() {
      switch model.phase {
      case .offer, .connecting:
        break

      default:
        model.createOffer()
      }
    }
  }

#endif
