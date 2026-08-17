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
  /// The minimum comfortable tap target.
  private static let tapTargetSide: CGFloat = 44

  /// Pulls the tap target's slack back out of the row's layout.
  private static let tapTargetOverflow: CGFloat = -10

  /// The complete holder name read from the primed identity certificate.
  internal let holder: String

  /// Removes the device-local identity after the parent confirms the action.
  internal let forget: () -> Void

  internal var body: some View {
    Section {
      HStack {
        LabeledContent {
          Text(holder)
            .textSelection(.enabled)
        } label: {
          PersonRowLabel(configured: true)
        }
        .accessibilityIdentifier("identityStatus")
        // The forget action lives on the row it removes, pinned to
        // the trailing edge and centered in the row's height; the
        // confirmation dialog still stands in front of it.
        Button(role: .destructive, action: forget) {
          Image(systemName: "minus.circle")
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .frame(width: Self.tapTargetSide, height: Self.tapTargetSide)
        .contentShape(Rectangle())
        .padding(Self.tapTargetOverflow)
        .accessibilityLabel(Text("Forget identity"))
        .accessibilityIdentifier("forgetCardIdentityButton")
      }
    } header: {
      Text("Identity")
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
    }
  }
}
