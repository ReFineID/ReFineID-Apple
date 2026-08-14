// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// Who the connected reader's card says they are, one row per card.
  ///
  /// The same row the Mac window shows, for the same reason: the holder
  /// needs to know whose identity is live before spending a PIN on it,
  /// and someone carrying two cards needs to see which one is in the
  /// reader. It is also what a signing screen would be built on top of,
  /// so it is the identity and not the cable that this screen states.
  ///
  /// The reader message survives as the fallback for a card whose name
  /// cannot be read: a live token with no readable name is still a card
  /// present, and saying nothing at all would read as nothing working.
  internal struct ReaderIdentityConnectedView: View {
    /// Breathing room around the fallback message.
    private static let messagePadding: CGFloat = 32

    internal let model: ReaderIdentityModeModel

    /// The holder names read from the live reader tokens, in the order
    /// their tokens are listed.
    @State private var holders: [String] = []

    internal var body: some View {
      content
        .navigationTitle("ReFineID")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
          if !model.hasActivationRequiredCard, model.liveReaderTokenCount > 0 {
            ToolbarItem(placement: .topBarTrailing) {
              NavigationLink {
                CardManagementView(readerCardIsPresent: true)
              } label: {
                Image(systemName: "key")
                  .accessibilityLabel(Text("Change or Reset PINs"))
              }
              .accessibilityIdentifier("manageCard")
            }
          }
        }
        .task(id: model.liveReaderTokenIdentifiers) {
          await readHolders()
        }
    }

    /// The identities, or the fallback while none has a name.
    @ViewBuilder private var content: some View {
      if model.hasActivationRequiredCard {
        CardManagementView(
          readerCardIsPresent: true,
          activationRequired: true
        )
      } else if holders.isEmpty {
        Text(message)
          .font(.title2.weight(.semibold))
          .multilineTextAlignment(.center)
          .padding(Self.messagePadding)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Form {
          Section("Identity") {
            ForEach(holders, id: \.self) { holder in
              LabeledContent("Person") {
                Text(holder)
                  .textSelection(.enabled)
              }
            }
          }
        }
      }
    }

    /// Distinguishes one usable reader from several without exposing
    /// card data.
    private var message: String {
      if model.liveReaderTokenCount == 1 {
        String(localized: "USB-C reader connected with ID card.")
      } else {
        String(localized: "USB-C readers connected with ID cards.")
      }
    }

    /// Reads each live token's published name off the main actor.
    ///
    /// Each token is asked for by name. The tokens are the ones the
    /// model proved live, so no dormant registration is consulted and
    /// no near-field read is provoked - see
    /// ``PublishedIdentityName/name(ofTokenIdentifier:)``.
    private func readHolders() async {
      let identifiers = model.liveReaderTokenIdentifiers
      holders = await Task.detached(priority: .utility) {
        identifiers.compactMap { identifier in
          PublishedIdentityName.name(ofTokenIdentifier: identifier)
        }
      }.value
    }
  }

#endif
