// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(iOS) && REFINEID_REMOTE_CARD
  extension CardCredentialsView {

    // MARK: Nested Types

    private enum RemotePairingLayout {
      static let inputSpacing: CGFloat = 8
      static let promptSpacing: CGFloat = 4
      static let verticalPadding: CGFloat = 4
    }

    // MARK: Computed Properties

    private var pairingCodeBinding: Binding<String> {
      Binding(
        get: { RappPairingCode.formatted(pairingCodeDigits) },
        set: { newValue in
          let digits = RappPairingCode.normalize(newValue)
          pairingCodeDigits = digits
          if RappPairingCode.isValid(digits) {
            isPairingCodeFocused = false
            pairingModel.acceptPairingCode(digits)
          } else if pairingModel.phase != .codeEntry {
            pairingModel.startCodeEntry()
          }
        }
      )
    }

    @ViewBuilder internal var remoteRouteRow: some View {
      HStack {
        Label(
          String(localized: "Remote"),
          systemImage: remoteCardAvailable
            ? "key.radiowaves.forward"
            : "key.radiowaves.forward.slash"
        )
        .foregroundStyle(
          remoteCardAvailable
            ? AnyShapeStyle(Color.primary)
            : AnyShapeStyle(.secondary)
        )
        Spacer()
        if remoteCardAvailable {
          Button(
            isPairingInputActive
              ? String(localized: "Cancel")
              : String(localized: "Connect")
          ) {
            togglePairingInput()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier("remoteConnectButton")
        }
      }
      .accessibilityIdentifier("remoteCard")
    }

    @ViewBuilder internal var remotePairingInputRow: some View {
      VStack(alignment: .leading, spacing: RemotePairingLayout.inputSpacing) {
        HStack {
          TextField("123 456", text: pairingCodeBinding)
            .font(.system(.body, design: .monospaced, weight: .semibold))
            .keyboardType(.numberPad)
            .focused($isPairingCodeFocused)
            .accessibilityIdentifier("pairingCodeEntry")

          if case .connecting = pairingModel.phase {
            ProgressView()
              .controlSize(.small)
          }
        }

        if case .failed(let error) = pairingModel.phase {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        } else if case .connecting = pairingModel.phase {
          Text(String(localized: "Connecting to remote reader..."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, RemotePairingLayout.verticalPadding)
    }

    @ViewBuilder private var remoteActionContent: some View {
      if case .offer(let code) = pairingModel.phase {
        remoteOfferContent(code)
      } else if case .connecting = pairingModel.phase {
        remoteConnectingContent
      } else {
        Button(String(localized: "Connect Remote Reader")) {
          if remoteModel.hasPair {
            remoteModel.connect()
          } else {
            pairingModel.createOffer()
          }
        }
        .accessibilityIdentifier("connectRemoteReader")
      }
    }

    @ViewBuilder internal var remoteIdentityContent: some View {
      switch remoteModel.phase {
      case .connecting:
        ProgressView()
      case .identity(let holder):
        remoteHolderContent(holder)
      case .idle, .failed:
        remoteActionContent
      }
    }

    private var remoteConnectingContent: some View {
      HStack {
        ProgressView()
          .controlSize(.small)
        Text(String(localized: "Connecting..."))
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          pairingModel.cancel()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
      }
    }

    internal var remoteReaderSection: some View {
      Section {
        LabeledContent {
          remoteIdentityContent
        } label: {
          PersonRowLabel(configured: remoteModel.holder != nil)
        }
        if remoteModel.phase == .failed {
          Text(remoteModel.failureText ?? String(localized: "The remote card could not be read."))
            .foregroundStyle(.secondary)
        }
      } header: {
        compactSectionHeader("Identity")
      }
      .onValueChange(of: remoteModel.needsFreshPairing) { needsFresh in
        if needsFresh {
          remoteModel.acknowledgeFreshPairing()
          pairingModel.createOffer()
        }
      }
      .onReceive(pairingModel.$phase) { phase in
        if case .paired = phase {
          remoteModel.refreshThenConnect()
        }
      }
    }

    // MARK: Functions

    private func togglePairingInput() {
      withAnimation {
        if isPairingInputActive {
          isPairingInputActive = false
          pairingModel.cancel()
          pairingCodeDigits = ""
        } else {
          isPairingInputActive = true
          pairingModel.startCodeEntry()
          pairingCodeDigits = ""
          isPairingCodeFocused = true
        }
      }
    }

    private func remoteHolderContent(_ holder: String) -> some View {
      HStack(spacing: Self.holderActionSpacing) {
        Text(holder)
          .textSelection(.enabled)
          .accessibilityIdentifier("remoteCardHolder")
        Button {
          remoteModel.forget()
        } label: {
          Image(systemName: "minus.circle.fill")
            .foregroundStyle(.red)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("forgetRemoteIdentity")
        .accessibilityLabel(String(localized: "Forget identity"))
      }
    }

    private func remoteOfferContent(_ code: String) -> some View {
      HStack {
        VStack(alignment: .leading, spacing: RemotePairingLayout.promptSpacing) {
          Text(RappPairingCode.formatted(code))
            .font(.system(.title3, design: .monospaced, weight: .bold))
            .accessibilityIdentifier("pairingCode")
            .accessibilityLabel(RappPairingCode.formatted(code))
          Text(String(localized: "Enter this code on your iPhone"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          pairingModel.cancel()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(String(localized: "Cancel"))
      }
    }
  }
#else
  extension CardCredentialsView {
    internal var remoteReaderSection: some View {
      EmptyView()
    }
  }
#endif
