// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// What sits under the setup screen, when anything does.
///
/// A demonstration says so for as long as it runs, in the place a
/// development build offers its diagnostics. A shipped build doing the
/// job it was installed for has neither, and this is empty: the setup
/// screen ends at its last product control.
internal struct CardSetupFooter: View {
  private static let padding: CGFloat = 12

  /// Whether this run is demonstrating the flow without a card.
  internal let isDemonstration: Bool

  internal var body: some View {
    if isDemonstration {
      demonstration
    } else {
      development
    }
  }

  /// The standing notice that nothing on the screen came off a card.
  ///
  /// A warning bar and not a caption: it names the mode in capitals, on
  /// red, across the whole width and into the home indicator, because
  /// the one thing a person must never do with this screen is believe
  /// it. No symbol beside it -- the bar is the signal, and a small
  /// picture next to shouted text only makes the text smaller.
  ///
  /// White on a dark red rather than green on red. Red and green are the
  /// pair most colour-blind readers cannot separate, while the darker red
  /// keeps the standing warning above the text contrast floor in every
  /// appearance without relying on colour as its only signal.
  @ViewBuilder private var demonstration: some View {
    #if os(iOS)
      Text("DEMO MODE")
        .font(.headline)
        .foregroundStyle(.white)
        .accessibilityIdentifier("demoModeNotice")
        .padding(.vertical, Self.padding)
        .frame(maxWidth: .infinity)
        .background(
          Color(red: 0.68, green: 0.04, blue: 0.04),
          ignoresSafeAreaEdges: .bottom)
    #endif
  }

  /// The route into diagnostics, in development builds only.
  @ViewBuilder private var development: some View {
    #if DEBUG
      NavigationLink {
        DiagnosticsView()
      } label: {
        Label("Diagnostics", systemImage: "stethoscope")
      }
      .accessibilityIdentifier("diagnosticsButton")
      .padding(.vertical, Self.padding)
      .frame(maxWidth: .infinity)
      .background(.bar)
    #endif
  }
}
