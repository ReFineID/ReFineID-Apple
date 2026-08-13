// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The finished state: who the stored card says they are.
///
/// The same row a connected reader shows, read from the stored prime
/// rather than from the token: a registered card's token has to be minted
/// before the keychain can answer for it, and minting one over near field
/// opens a scan sheet on a screen nobody asked to scan from. A check mark
/// stands in when the name will not parse, because the identity is set
/// either way and that is what this row reports.
internal struct CardIdentitySection: View {
  /// Whether the name to show is a demonstration's test person.
  internal let isDemonstration: Bool

  internal var body: some View {
    Section {
      LabeledContent("Person") {
        if let holder = primedHolder {
          Text(holder)
            .textSelection(.enabled)
        } else {
          Image(systemName: "checkmark")
            .foregroundStyle(.green)
            .accessibilityLabel("Set")
        }
      }
      .accessibilityIdentifier("identityStatus")
    }
  }

  /// Who the primed card names, or nil when no name can be read.
  ///
  /// A demonstration names its test person instead. That name is a string
  /// and not a certificate, so it is read from nowhere and published to
  /// nothing.
  private var primedHolder: String? {
    #if os(iOS)
      if isDemonstration {
        return DemoMode.holderName
      }
    #endif
    return PrimeStore.primedHolderNames().first
  }
}
