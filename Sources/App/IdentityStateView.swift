#if os(macOS)

  import SwiftUI

  /// Ready and who, what to do about it, or the settling state between.
  ///
  /// A card mints in well under a second, and for that moment it is
  /// present without an identity yet published. That is not a fault and
  /// must not be shouted as one: the row shows a calm line while it
  /// settles and only warns once the state has lasted long enough to
  /// mean something.
  internal struct IdentityStateView: View {
    /// How long a card may be present without a published identity
    /// before the row says to re-insert it.
    ///
    /// Matched to the driver's own recovery delay: an ordinary mint
    /// finishes well inside it, and the software reinsertion that
    /// recovers a stuck card is tried at the same moment, so the
    /// warning appears only once that has had its chance. Shorter, and
    /// every insertion flashes orange for a fraction of a second.
    private static let settleDelaySeconds = 3

    /// The same, as the sleep wants it.
    private static let settleDelay: Duration = .seconds(settleDelaySeconds)

    /// What the login row keys on.
    internal let availability: LoginIdentityModel.Availability

    /// Who the card says they are, read when a card is ready.
    ///
    /// Held here rather than in the model because it is worth nothing
    /// once the card is gone, and the row is the only thing that shows
    /// it.
    @State private var holder: String?

    /// Whether the unready state has lasted long enough to warn about.
    @State private var settled = false

    internal var body: some View {
      content
        .task(id: availability) { await track() }
    }

    @ViewBuilder private var content: some View {
      switch availability {
      case .ready:
        // Who is about to sign: someone with two cards can see which
        // one is in the reader before spending a PIN on it.
        Text(holder ?? "Ready")
          .foregroundStyle(holder == nil ? AnyShapeStyle(.green) : AnyShapeStyle(.primary))
          .textSelection(.enabled)
      case .cardWithoutIdentity:
        if settled {
          Text("Card detected, not ready - if this lasts, re-insert it")
            .foregroundStyle(.orange)
        } else {
          Text("Reading the card…")
            .foregroundStyle(.secondary)
        }
      case .noCard:
        Text("Insert your card")
          .foregroundStyle(.secondary)
      }
    }

    /// Follows one availability: reads the name when ready, and lets the
    /// unready state settle before it is called a problem.
    ///
    /// Re-run on every change and cancelled on the one before it, so a
    /// card that becomes ready within the delay cancels the warning it
    /// would otherwise have shown. The name is read off the main actor
    /// and never blocks the row.
    private func track() async {
      holder =
        availability == .ready
        ? await Task.detached(priority: .utility) { PublishedIdentityName.current() }.value
        : nil
      guard availability == .cardWithoutIdentity else {
        settled = false
        return
      }
      settled = false
      try? await Task.sleep(for: Self.settleDelay)
      if !Task.isCancelled {
        settled = true
      }
    }
  }

#endif
