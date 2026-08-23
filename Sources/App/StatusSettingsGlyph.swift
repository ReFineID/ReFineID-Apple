// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The one status control: PIN health on the key, link state on the waves.
  internal struct StatusSettingsGlyph: View {
    private enum Layout {
      static let glyphPointSize: CGFloat = 22
    }

    internal let pinLevel: CredentialRetryHealth.Level?
    internal let routeAvailable: Bool

    internal var body: some View {
      Image(systemName: "key.radiowaves.forward")
        .font(.system(size: Layout.glyphPointSize))
        .symbolRenderingMode(.palette)
        .foregroundStyle(keyColor, waveColor)
        .replacingSymbolPlainly()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Change or Reset PINs"))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
      #if REFINEID_REMOTE_CARD
        let link =
          PersistentTokenRegistry.shared.holderIsAdvertising
          ? String(localized: "Phone connected")
          : String(localized: "Phone not connected")
        if let pins = pinLevel?.accessibilityValue {
          return pins + ", " + link
        }
        return link
      #else
        pinLevel?.accessibilityValue ?? ""
      #endif
    }

    /// Green, yellow, or red from the card's retry class; grey without a card.
    private var keyColor: Color {
      guard routeAvailable, let pinLevel else { return .secondary }
      return pinLevel.color
    }

    /// Green while the paired phone is advertising; grey when it is not.
    private var waveColor: Color {
      #if REFINEID_REMOTE_CARD
        PersistentTokenRegistry.shared.holderIsAdvertising ? .green : .secondary
      #else
        .secondary
      #endif
    }
  }

#endif
