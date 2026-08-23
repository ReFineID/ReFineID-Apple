// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(iOS) && REFINEID_REMOTE_CARD
  extension CardCredentialsView {
    // MARK: Nested Types

    private enum RemotePairingLayout {
      static let inputSpacing: CGFloat = 8
      static let tapTargetSide: CGFloat = 44
      static let tapTargetOverflow: CGFloat = -10
      static let forgetButtonGap: CGFloat = 4
    }

    // MARK: Computed Properties

    private var pairingCodeFirstBinding: Binding<String> {
      Binding(
        get: {
          String(pairingCodeDigits.prefix(RappPairingCode.groupSize))
        },
        set: { newValue in
          let incoming = RappPairingCode.normalize(newValue)
          if incoming.count > RappPairingCode.groupSize {
            applyPairingDigits(incoming)
            pairingCodeGroup =
              RappPairingCode.isValid(incoming) ? nil : .second
            return
          }
          let second = String(
            pairingCodeDigits.dropFirst(RappPairingCode.groupSize))
          applyPairingDigits(incoming + second)
          if incoming.count == RappPairingCode.groupSize {
            pairingCodeGroup = .second
          }
        }
      )
    }

    private var pairingCodeSecondBinding: Binding<String> {
      Binding(
        get: {
          String(pairingCodeDigits.dropFirst(RappPairingCode.groupSize))
        },
        set: { newValue in
          let first = String(
            pairingCodeDigits.prefix(RappPairingCode.groupSize))
          let second = String(
            RappPairingCode.normalize(newValue).prefix(RappPairingCode.groupSize)
          )
          applyPairingDigits(first + second)
          if second.isEmpty {
            pairingCodeGroup = .first
          }
        }
      )
    }

    @ViewBuilder internal var remoteRouteRow: some View {
      HStack(spacing: RemotePairingLayout.inputSpacing) {
        Group {
          if remoteCardAvailable {
            RemotePairingGlyph(isConnected: pairingModel.hasActivePairs)
          } else {
            PersonRowLabel.cardIcon(
              systemName: "key.radiowaves.forward",
              lit: false
            )
          }
        }
        .frame(width: PersonRowLabel.iconWidth)
        Text(String(localized: "Remote"))
          .foregroundStyle(
            remoteCardAvailable
              ? AnyShapeStyle(Color.primary)
              : AnyShapeStyle(.secondary)
          )
        Spacer()
        if remoteCardAvailable {
          remoteRouteTrailingControls
        }
      }
      .buttonStyle(.borderless)
      .accessibilityIdentifier("remoteCard")
      .onAppear {
        pairingModel.refresh()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappPairingModel.pairingsDidChangeNotification)
      ) { _ in
        pairingModel.refresh()
      }
    }

    @ViewBuilder private var remoteRouteTrailingControls: some View {
      if isPairingInputActive {
        inlinePairingControls
      } else if pairingModel.hasActivePairs {
        HStack(spacing: RemotePairingLayout.forgetButtonGap) {
          connectedStatusChip
          Button(role: .destructive) {
            withAnimation {
              pairingModel.revokeAll()
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
          .accessibilityLabel(Text("Disconnect"))
          .accessibilityIdentifier("remoteDisconnectButton")
        }
      } else {
        Button(String(localized: "Connect")) {
          togglePairingInput()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("remoteConnectButton")
      }
    }

    private var connectedStatusChip: some View {
      Button(String(localized: "Connected")) {
        // Status only; the minus control drops the pairing.
      }
      .buttonStyle(.bordered)
      .tint(.green)
      .controlSize(.small)
      .allowsHitTesting(false)
      .accessibilityRemoveTraits(.isButton)
    }

    @ViewBuilder private var inlinePairingControls: some View {
      HStack(spacing: 0) {
        pairingCodeGroupField(
          prompt: "123",
          text: pairingCodeFirstBinding,
          group: .first
        )
        .accessibilityIdentifier("pairingCodeEntry")
        Text(verbatim: " ")
          .font(.system(.body, design: .monospaced, weight: .bold))
          .accessibilityHidden(true)
        pairingCodeGroupField(
          prompt: "456",
          text: pairingCodeSecondBinding,
          group: .second
        )
        if case .connecting = pairingModel.phase {
          ProgressView()
            .controlSize(.small)
        }
      }
    }

    @ViewBuilder private var remoteActionContent: some View {
      if case .offer(let code) = pairingModel.phase {
        Text(RappPairingCode.formatted(code))
          .font(.system(.body, design: .monospaced, weight: .bold))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.trailing)
          .accessibilityIdentifier("pairingCode")
      } else if case .connecting = pairingModel.phase {
        ProgressView()
          .controlSize(.small)
      } else {
        Button(String(localized: "Connect")) {
          withAnimation {
            pairingModel.createOffer()
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("connectRemoteReader")
      }
    }

    @ViewBuilder private var remoteIdentityRow: some View {
      if case .identity(let holder) = remoteModel.phase,
        PersistentTokenRegistry.shared.holderLine != nil
      {
        HStack {
          LabeledContent {
            Text(holder)
              .textSelection(.enabled)
              .accessibilityIdentifier("remoteCardHolder")
          } label: {
            PersonRowLabel(configured: true)
          }
          Spacer(minLength: RemotePairingLayout.forgetButtonGap)
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

    private func pairingCodeGroupField(
      prompt: String,
      text: Binding<String>,
      group: PairingCodeGroup
    ) -> some View {
      TextField(prompt, text: text)
        .font(.system(.body, design: .monospaced, weight: .bold))
        .foregroundStyle(.primary)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.leading)
        .focused($pairingCodeGroup, equals: group)
        .frame(width: Layout.pairingGroupFieldWidth)
    }

    private func applyPairingDigits(_ digits: String) {
      let normalized = RappPairingCode.normalize(digits)
      pairingCodeDigits = normalized
      if RappPairingCode.isValid(normalized) {
        pairingCodeGroup = nil
        pairingModel.acceptPairingCode(normalized)
      } else if pairingModel.phase != .codeEntry {
        pairingModel.startCodeEntry()
      }
    }

    private func togglePairingInput() {
      withAnimation {
        if isPairingInputActive {
          isPairingInputActive = false
          pairingModel.cancel()
          pairingCodeDigits = ""
          pairingCodeGroup = nil
        } else {
          isPairingInputActive = true
          pairingModel.startCodeEntry()
          pairingCodeDigits = ""
          pairingCodeGroup = .first
        }
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
