// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(iOS) && REFINEID_REMOTE_CARD
  extension CardCredentialsView {

    // MARK: Nested Types

    private enum RemotePairingLayout {
      static let inputSpacing: CGFloat = 8
      static let inlineSpacing: CGFloat = 6
      static let promptSpacing: CGFloat = 4
      static let inlineInputWidth: CGFloat = 90
      static let tapTargetSide: CGFloat = 44
      static let tapTargetOverflow: CGFloat = -10
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
      HStack(spacing: RemotePairingLayout.inputSpacing) {
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
          if isPairingInputActive {
            inlinePairingControls
          } else {
            Button(String(localized: "Connect")) {
              togglePairingInput()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("remoteConnectButton")
          }
        }
      }
      .accessibilityIdentifier("remoteCard")
    }

    @ViewBuilder private var inlinePairingControls: some View {
      HStack(spacing: RemotePairingLayout.inlineSpacing) {
        TextField("123 456", text: pairingCodeBinding)
          .font(.system(.body, design: .monospaced, weight: .semibold))
          .keyboardType(.numberPad)
          .multilineTextAlignment(.trailing)
          .focused($isPairingCodeFocused)
          .frame(width: RemotePairingLayout.inlineInputWidth)
          .accessibilityIdentifier("pairingCodeEntry")

        if case .connecting = pairingModel.phase {
          ProgressView()
            .controlSize(.small)
        } else {
          Button {
            withAnimation {
              isPairingInputActive = false
              pairingModel.cancel()
              pairingCodeDigits = ""
            }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(String(localized: "Cancel"))
        }
      }
    }

    @ViewBuilder private var remoteActionContent: some View {
      if case .offer(let code) = pairingModel.phase {
        remoteOfferContent(code)
      } else if case .connecting = pairingModel.phase {
        remoteConnectingContent
      } else {
        Button(String(localized: "Connect Remote Reader")) {
          withAnimation {
            pairingModel.createOffer()
          }
        }
        .accessibilityIdentifier("connectRemoteReader")
      }
    }

    @ViewBuilder private var remoteIdentityRow: some View {
      if case .identity(let holder) = remoteModel.phase {
        HStack {
          LabeledContent {
            Text(holder)
              .textSelection(.enabled)
              .accessibilityIdentifier("remoteCardHolder")
          } label: {
            PersonRowLabel(configured: true)
          }
          Spacer(minLength: 0)
          Button(role: .destructive) {
            withAnimation {
              pairingModel.cancel()
              remoteModel.forget()
            }
          } label: {
            Image(systemName: "minus.circle")
              .font(.title3)
              .foregroundStyle(.red)
          }
          .buttonStyle(.plain)
          .frame(
            width: RemotePairingLayout.tapTargetSide,
            height: RemotePairingLayout.tapTargetSide
          )
          .contentShape(Rectangle())
          .padding(RemotePairingLayout.tapTargetOverflow)
          .accessibilityLabel(Text("Forget identity"))
          .accessibilityIdentifier("forgetRemoteIdentity")
        }
      } else {
        LabeledContent {
          remoteActionContent
        } label: {
          PersonRowLabel(configured: false)
        }
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
        remoteIdentityRow
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
