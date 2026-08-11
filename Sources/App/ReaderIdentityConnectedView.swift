// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// The transport-state UI while attached readers own ReFineID identity.
  internal struct ReaderIdentityConnectedView: View {
    /// Breathing room around the deliberately minimal reader message.
    private static let messagePadding: CGFloat = 32

    internal let model: ReaderIdentityModeModel

    internal var body: some View {
      Text(message)
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)
        .padding(Self.messagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("ReFineID")
        .navigationBarTitleDisplayMode(.large)
    }

    /// Distinguishes one usable reader from several without exposing card data.
    private var message: String {
      if model.liveReaderTokenCount == 1 {
        "USB-C reader connected with Finnish ID card."
      } else {
        "USB-C readers connected with Finnish ID cards."
      }
    }
  }

#endif
