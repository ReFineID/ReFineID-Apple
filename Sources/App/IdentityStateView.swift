#if os(macOS)

  import SwiftUI

  /// Ready, or what to do about it - and the one state between, named
  /// honestly instead of asking for a card that is already in the
  /// reader.
  internal struct IdentityStateView: View {
    /// What the login row keys on.
    internal let availability: LoginIdentityModel.Availability

    internal var body: some View {
      switch availability {
      case .ready:
        Image(systemName: "checkmark")
          .foregroundStyle(.green)
          .accessibilityLabel("Ready")
      case .cardWithoutIdentity:
        Text("Card detected, not ready - if this lasts, re-insert it")
          .foregroundStyle(.orange)
      case .noCard:
        Text("Insert your card")
          .foregroundStyle(.secondary)
      }
    }
  }

#endif
