// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

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
    /// One tracked event.
    ///
    /// Token-list movement matters only while an identity is published,
    /// because only then is there a holder name to re-read.
    private enum TrackKey: Equatable {
      case availability(LoginIdentityModel.Availability)
      case ready(generation: Int, borrowed: String?)
    }

    #if DEBUG
      /// Row outcomes, in development builds only.
      ///
      /// States, never a name. A production build writes no
      /// diagnostics.
      private static let log = Logger(
        subsystem: "fi.refineid.ReFineID", category: "identity-row"
      )
    #endif

    /// What the login row keys on.
    internal let availability: LoginIdentityModel.Availability

    /// A completed activation check and recovery found no usable
    /// identity.
    ///
    /// Until that event, absence means that the card is still being
    /// read rather than that it failed.
    internal let warnsUnavailableCard: Bool

    /// The model, watched so a token event re-reads the name even
    /// when the availability itself did not move.
    private let model = LoginIdentityModel.shared

    /// Who the card says they are, read when a card is ready.
    ///
    /// Held here rather than in the model because it is worth nothing
    /// once the card is gone, and the row is the only thing that shows
    /// it.
    @State private var holder: String?

    /// The person line the remote-card registry already holds.
    ///
    /// Used when the keychain has not yet listed the borrowed token
    /// the registry just published.
    private var borrowedHolderLine: String? {
      #if REFINEID_REMOTE_CARD
        PersistentTokenRegistry.shared.holderLine
      #else
        nil
      #endif
    }

    /// The event which can change the row's asynchronous contents.
    private var trackKey: TrackKey {
      switch availability {
      case .ready:
        .ready(generation: model.generation, borrowed: borrowedHolderLine)

      case .cardWithoutIdentity, .noCard:
        .availability(availability)
      }
    }

    internal var body: some View {
      content
        .task(id: trackKey) {
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
        Text(holder ?? borrowedHolderLine ?? "")
          .textSelection(.enabled)

      case .cardWithoutIdentity:
        if warnsUnavailableCard {
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

    /// Follows one availability and reads the name when ready.
    ///
    /// The name is read off the main actor and never blocks the row.
    private func track() async {
      #if DEBUG
        Self.log.info("track: \(String(describing: self.availability))")
      #endif
      switch availability {
      case .ready:
        // A read that answers nothing while the token is listed is
        // left alone: this process's view of the token items has been
        // observed answering empty against an identity Safari was
        // using at that same moment, so an empty answer proves
        // nothing and must never cost a registration anything.
        let tokenIDs = Array(model.ownedTokenIDs)
        holder = await Task.detached(priority: .utility) {
          PublishedIdentityName.current(tokenIDs: tokenIDs)
        }.value
        if holder == nil {
          holder = borrowedHolderLine
        }

      case .cardWithoutIdentity:
        holder = nil

      case .noCard:
        holder = nil
      }
    }
  }

#endif
