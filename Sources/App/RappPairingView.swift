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
        servingCardScanner
      }
    }
    .onAppear {
      model.refresh()
      if borrowsOnly {
        model.createOffer()
        #if os(iOS)
          ScreenBrightness.raiseForScanning()
        #endif
      } else {
        model.scanOffer()
      }
    }
    // The code is on screen to be scanned, so a scan that lands is the end
    // of this screen: it leaves, and what it produced is read behind it.
    .onValueChange(of: model.phase) { phase in
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

  /// The camera, which is the whole of what a card holder does here.
  ///
  /// A device that serves a card opens this screen to read one code. A
  /// list of pairings and a button to begin would be two steps in front of
  /// the only step there is, and the pairing it makes is shown on the
  /// screen this came from.
  @ViewBuilder private var servingCardScanner: some View {
    #if os(iOS)
      ZStack {
        Color.black.ignoresSafeArea()
        RappOfferScanner { model.acceptScannedOffer($0) }
          .ignoresSafeArea()
          .accessibilityIdentifier("pairingScanner")
        if case .connecting = model.phase {
          ProgressView()
            .controlSize(.large)
            .tint(.white)
        }
      }
    #else
      EmptyView()
    #endif
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

}
