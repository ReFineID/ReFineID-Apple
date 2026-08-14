// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The finished state: who the stored card says they are.
///
/// The same row a connected reader shows, read from the stored prime
/// rather than from the token: a registered card's token has to be minted
/// before the keychain can answer for it, and minting one over near field
/// opens a scan sheet on a screen nobody asked to scan from.
internal struct CardIdentitySection: View {
  /// The complete holder name read from the primed identity certificate.
  internal let holder: String

  internal var body: some View {
    Section("Identity") {
      LabeledContent("Person") {
        Text(holder)
          .textSelection(.enabled)
      }
      .accessibilityIdentifier("identityStatus")
    }
  }
}
