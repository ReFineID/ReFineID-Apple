#if os(macOS)

  import SwiftUI

  /// Ready, or what to do about it - and the one state between, named
  /// honestly instead of asking for a card that is already in the
  /// reader.
  internal struct IdentityStateView: View {
    /// What the login row keys on.
    internal let availability: LoginIdentityModel.Availability

    /// Who the card says they are, read when the row appears.
    ///
    /// Held here rather than in the model because it is worth nothing
    /// once the card is gone, and the row is the only thing that shows
    /// it.
    @State private var holder: String?

    internal var body: some View {
      switch availability {
      case .ready:
        // Who is about to sign: someone with two cards can see which
        // one is in the reader before spending a PIN on it.
        Text(holder ?? "Ready")
          .foregroundStyle(holder == nil ? AnyShapeStyle(.green) : AnyShapeStyle(.primary))
          .textSelection(.enabled)
          .task { holder = PublishedIdentityName.current() }
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
