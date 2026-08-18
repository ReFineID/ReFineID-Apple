// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if !REFINEID_LOCAL_CARD && os(iOS)

  import SwiftUI

  /// The whole screen of a device that has no card of its own.
  ///
  /// Such a device asks a paired phone for the card and publishes the
  /// certificate that comes back, so there are three things worth showing:
  /// the one action, the code the phone scans, and the person it reached.
  /// Verification joins them because it reads a document, never a card.
  internal struct RequesterIdentityView: View {
    /// The pairing code's side, large enough for a phone to read it
    /// across the width of a desk.
    private static let codeSide: CGFloat = 320

    /// The space between the screen's few elements.
    private static let spacing: CGFloat = 24

    @StateObject private var pairing = RappPairingModel()
    @StateObject private var remote = RemoteCardModel()
    @State private var showsDocumentVerify = false

    internal var body: some View {
      NavigationStack {
        VStack(spacing: Self.spacing) {
          content
          if isResting {
            verifyAction
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        // The root carries no title and no controls of its own, so its bar
        // would be an empty strip above a screen with two buttons on it.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showsDocumentVerify) {
          VerifyDocumentView()
        }
        .onAppear {
          pairing.refresh()
          remote.refresh()
        }
        .onValueChange(of: pairing.phase) { phase in
          // A completed ceremony is half the answer. The certificate it
          // authorizes is the half a browser asks for, so read it now
          // rather than leaving a second action to find.
          if case .paired = phase {
            remote.refresh()
            remote.connect()
          }
        }
        .onValueChange(of: pairing.pairs.count) { _ in
          remote.refresh()
        }
      }
    }

    @ViewBuilder private var content: some View {
      if let holder = remote.holder {
        identity(holder)
      } else if case .offer(let uri) = pairing.phase {
        pairingCode(uri)
      } else if isWorking {
        ProgressView()
      } else {
        connectAction
      }
    }

    /// Whether either half of the exchange is mid-flight.
    private var isWorking: Bool {
      remote.phase == .connecting || pairing.phase == .connecting
    }

    /// Whether the screen is waiting on the holder rather than on a phone.
    ///
    /// A code on screen and a read in flight are both passing states that
    /// end on their own, and a second action beside them is one the holder
    /// has no reason to take yet.
    private var isResting: Bool {
      if case .offer = pairing.phase { return false }
      return !isWorking
    }

    /// The verification screen's own name, taken from where it defines it.
    private var verifyTitle: String {
      String(
        localized: "verify.title",
        defaultValue: "Verify",
        table: "DocumentSigning")
    }

    /// Reading a document asks for no card, no phone, and no identity, so
    /// it stands on its own beside the one action that needs all three.
    private var verifyAction: some View {
      Button(verifyTitle) { showsDocumentVerify = true }
        .accessibilityIdentifier("verifyDocuments")
    }

    /// The last failure from whichever half produced one.
    private var failure: String? {
      if case .failed(let message) = pairing.phase {
        return message
      }
      if remote.phase == .failed {
        return remote.failureText
          ?? String(localized: "The remote card could not be read.")
      }
      return nil
    }

    private var connectAction: some View {
      VStack(spacing: Self.spacing) {
        Button(String(localized: "Connect Remote Reader")) {
          // A phone already paired can be asked straight away; one that is
          // not needs the code first, and that code is the next thing on
          // screen either way.
          if remote.hasPair {
            remote.connect()
          } else {
            pairing.createOffer()
          }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("connectRemoteReader")
        if let failure {
          Text(failure)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }
    }

    private func pairingCode(_ uri: String) -> some View {
      VStack(spacing: Self.spacing) {
        if let image = RappPairingCode.image(uri) {
          image
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: Self.codeSide, height: Self.codeSide)
            .accessibilityLabel(Text("Pairing QR code"))
        }
        // A phone that never arrives would otherwise hold the screen until
        // the offer expires.
        Button(String(localized: "Cancel")) { pairing.cancel() }
      }
    }

    private func identity(_ holder: String) -> some View {
      HStack(spacing: Self.spacing) {
        Text(holder)
          .font(.title3)
          .textSelection(.enabled)
          .accessibilityIdentifier("remoteCardHolder")
        Button(role: .destructive, action: removeIdentity) {
          Image(systemName: "minus.circle")
            .font(.title2)
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Forget identity"))
        .accessibilityIdentifier("removePairedDevice")
      }
    }

    /// Drops the pairing the identity was read through, which leaves the
    /// screen with the one action it started with.
    private func removeIdentity() {
      let selected = pairing.pairs.first { pair in
        pair.pairID == pairing.selectedPairID
      }
      guard let pair = selected ?? pairing.pairs.first else { return }
      pairing.revoke(pair)
    }
  }

#endif
