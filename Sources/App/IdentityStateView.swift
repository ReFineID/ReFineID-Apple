#if os(macOS)

  import os.log
  import SwiftUI

  /// Who the card says they are, what to do about it, or the settling
  /// state between.
  ///
  /// A card mints in well under a second, and for that moment it is
  /// present without an identity yet published. That is not a fault and
  /// must not be shouted as one: the row shows a calm line while it
  /// settles and only warns once the state has lasted long enough to
  /// mean something.
  internal struct IdentityStateView: View {
    /// One tracked moment: the availability and the token listing's
    /// generation, either of whose movement re-reads the row.
    private struct TrackKey: Equatable {
      let availability: LoginIdentityModel.Availability
      let generation: Int
    }

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
    /// Row outcomes, visible in the unified log for field reports.
    ///
    /// States only; never a name.
    private static let log = Logger(
      subsystem: "fi.refineid.ReFineID", category: "identity-row"
    )

    /// What the login row keys on.
    internal let availability: LoginIdentityModel.Availability

    /// The model, watched so a token event re-reads the name even
    /// when the availability itself did not move.
    private let model = LoginIdentityModel.shared

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
        .task(id: TrackKey(availability: availability, generation: model.generation)) {
          await track()
        }
    }

    @ViewBuilder private var content: some View {
      switch availability {
      case .ready:
        // Who is about to sign: someone with two cards can see which
        // one is in the reader before spending a PIN on it. Until the
        // name is read the row shows nothing - a claim without the
        // name behind it is not worth showing. The empty text is
        // still a rendered view: a structurally absent one would
        // never run the task that reads the name.
        Text(holder ?? "")
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
      Self.log.info("track: \(String(describing: self.availability))")
      settled = false
      switch availability {
      case .ready:
        // Armed before the read, because in the after-driver-update
        // shape the read itself is what hangs: a listed token whose
        // keychain items return only with the next card appearance.
        // A read that answers in time stands the recovery down; one
        // that hangs or answers nothing lets the model's one-shot
        // software reinsertion re-mint the card.
        model.attemptRecovery(unresolvedIdentity: true)
        holder = await Task.detached(priority: .utility) {
          PublishedIdentityName.current()
        }.value
        if holder != nil {
          model.cancelRecovery(cardLeft: false)
        }
      case .cardWithoutIdentity:
        holder = nil
        try? await Task.sleep(for: Self.settleDelay)
        if !Task.isCancelled {
          settled = true
        }
      case .noCard:
        holder = nil
      }
    }
  }

#endif
