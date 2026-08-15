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

  /// Removes the device-local identity after the parent confirms the action.
  internal let forget: () -> Void

  internal var body: some View {
    Section("Identity") {
      LabeledContent("Person") {
        Text(holder)
          .textSelection(.enabled)
      }
      .accessibilityIdentifier("identityStatus")

      Button(action: forget) {
        Label("Forget identity", systemImage: "person.badge.minus")
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.65, green: 0, blue: 0))
        .padding(.top, 12)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .accessibilityIdentifier("forgetCardIdentityButton")
    }
  }
}
