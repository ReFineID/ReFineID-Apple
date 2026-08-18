// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CoreImage
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
  import UIKit
  import VisionKit
#elseif os(macOS)
  import AppKit
#endif

internal struct RappPairingView: View {
  /// Sizes chosen so a pairing code stays readable to the other device's
  /// camera and the sheet never collapses below its own content.
  private enum Layout {
    /// How much of the shorter screen edge the code fills.
    ///
    /// A code that reaches the edges forces the camera back far enough to
    /// lose the modules, so it stops short of the screen.
    static let codeScreenFraction: CGFloat = 0.62

    /// The light border around the code, as a fraction of its side.
    static let codeQuietFraction: CGFloat = 0.08

    /// Smallest window that still shows the pair list without scrolling.
    static let sheetMinimumWidth: CGFloat = 440
    /// Smallest window height that keeps the code and its caption together.
    static let sheetMinimumHeight: CGFloat = 520
    /// Displayed edge of the pairing code, large enough to scan across a desk.
    static let pairingCodeEdge: CGFloat = 280
    /// Viewfinder height that leaves the code in frame at arm's length.
    static let scannerMinimumHeight: CGFloat = 320
    /// Corner rounding that matches the surrounding form rows.
    static let scannerCornerRadius: CGFloat = 16
  }

  @Environment(\.dismiss)
  private var dismiss
  @StateObject private var model = RappPairingModel()

  /// Whether this device can only borrow a card, never serve one.
  ///
  /// Such a device opens this screen for exactly one reason, so the code
  /// is what it shows: a list to choose from and a button to start would
  /// be two steps in front of the only step there is.
  private var borrowsOnly: Bool {
    #if os(iOS)
      return !SupportedCardTransports.offersNearField
    #else
      return false
    #endif
  }

  internal var body: some View {
    Group {
      if borrowsOnly {
        borrowedCardCode
      } else {
        servingCardForm
      }
    }
    .onAppear {
      model.refresh()
      if borrowsOnly {
        model.createOffer()
        #if os(iOS)
          ScreenBrightness.raiseForScanning()
        #endif
      }
    }
    // The code is on screen to be scanned, so a scan that lands is the end
    // of this screen: it leaves, and what it produced is read behind it.
    .onValueChange(of: model.phase) { phase in
      guard borrowsOnly else { return }
      switch phase {
      case .paired, .failed:
        dismiss()
      case .idle, .offer, .scanning, .connecting:
        break
      }
    }
    .onDisappear {
      model.cancel()
      #if os(iOS)
        ScreenBrightness.restore()
      #endif
    }
    #if os(macOS)
      .frame(minWidth: Layout.sheetMinimumWidth, minHeight: Layout.sheetMinimumHeight)
    #endif
  }

  /// The screen a device that can also serve a card shows: its pairings,
  /// the step that starts a new one, and how the current attempt is going.
  private var servingCardForm: some View {
    NavigationStack {
      Form {
        pairedDevices
        pairingAction
        pairingProgress
      }
      .navigationTitle("Remote Card")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Close") { dismiss() }
            .accessibilityIdentifier("closePairing")
        }
      }
    }
  }

  /// The surface the code is drawn on, in each platform's own paper.
  private var codeBackground: Color {
    #if os(iOS)
      Color(uiColor: .systemBackground)
    #else
      Color(nsColor: .windowBackgroundColor)
    #endif
  }

  /// The whole screen a borrowing device shows: the code, centred, as
  /// large as the screen allows.
  ///
  /// There is one thing to do here and one thing to look at, so there is
  /// nothing else on it. A sheet is dismissed by dragging it down.
  @ViewBuilder private var borrowedCardCode: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height) * Layout.codeScreenFraction
      ZStack {
        codeBackground.ignoresSafeArea()
        if case .offer(let uri) = model.phase, let image = RappPairingCode.image(uri) {
          image
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            // The generated code is dark modules on nothing, so it needs a
            // light field behind it and a quiet border around it: a camera
            // finds neither in a dark screen that reaches the edge.
            .padding(side * Layout.codeQuietFraction)
            .background(Color.white)
            .accessibilityIdentifier("pairingCode")
            .accessibilityLabel("Pairing code")
        } else {
          ProgressView()
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }

  @ViewBuilder private var pairedDevices: some View {
    if !model.pairs.isEmpty {
      Section("Paired devices") {
        ForEach(model.pairs, id: \.pairID) { pair in
          HStack {
            Label(
              model.displayName(for: pair),
              systemImage: pair.remotePlatformSymbol
            )
            Spacer()
            if model.selectedPairID == pair.pairID {
              Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Selected")
            }
          }
          Button("Remove this pairing", role: .destructive) {
            model.revoke(pair)
          }
          .accessibilityIdentifier("removePairedDevice")
        }
      }
    }
  }

  /// One connection at a time: pairing is offered only while no
  /// paired device exists.
  @ViewBuilder private var pairingAction: some View {
    if model.pairs.isEmpty {
      Section {
        #if os(macOS)
          Button("Pair a phone", systemImage: "qrcode") {
            model.createOffer()
          }
          .accessibilityIdentifier("pairPhone")
        #else
          // A device with an antenna holds the card and scans; a device
          // without one requests and shows the code to scan.
          if UIDevice.current.userInterfaceIdiom == .pad {
            Button("Pair a phone", systemImage: "qrcode") {
              model.createOffer()
            }
            .accessibilityIdentifier("pairPhone")
          } else {
            Button("Scan pairing code", systemImage: "qrcode.viewfinder") {
              model.scanOffer()
            }
            .accessibilityIdentifier("scanPairingCode")
          }
        #endif
      }
    }
  }

  @ViewBuilder private var pairingProgress: some View {
    switch model.phase {
    case .idle:
      EmptyView()
    case .offer(let uri):
      Section("Scan with ReFineID on the phone") {
        if let image = RappPairingCode.image(uri) {
          image
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: Layout.pairingCodeEdge, maxHeight: Layout.pairingCodeEdge)
            .accessibilityLabel("Pairing QR code")
            .accessibilityIdentifier("pairingCode")
        }
        ProgressView("Waiting for the phone")
      }
    case .scanning:
      #if os(iOS)
        Section("Scan the code shown on the other device") {
          RappOfferScanner { model.acceptScannedOffer($0) }
            .frame(minHeight: Layout.scannerMinimumHeight)
            .clipShape(.rect(cornerRadius: Layout.scannerCornerRadius))
            .accessibilityLabel("Pairing code scanner")
        }
      #endif
    case .connecting:
      Section { ProgressView("Establishing a secure connection") }
    case .paired(let pair):
      Section {
        Label("Secure pairing established", systemImage: "checkmark.shield")
          .foregroundStyle(.green)
        Text(pair.remotePlatformLabel)
      }
    case .failed(let message):
      Section {
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      }
    }
  }
}
