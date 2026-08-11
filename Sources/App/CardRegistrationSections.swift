// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import CryptoTokenKit
  import SwiftUI

  /// The single identity-creation action embedded below both credentials.
  ///
  /// Apple's NFC sheets own live progress and completion. Persistent card
  /// and Safari state belongs in Diagnostics, not below this button. The
  /// parent owns ``isRegistered``: a set identity replaces this whole
  /// setup section, not just this button.
  @available(iOS 26.0, *)
  internal struct CardRegistrationSections: View {
    /// Stable automation names; changing one never changes visible copy.
    private static let startIdentifier = "primeStartButton"
    private static let failedIdentifier = "primeFailed"
    /// Complete persistent identity state, read without waking NFC.
    ///
    /// A registration without its prime or stored PIN cannot sign. Treating
    /// that stale index as ready hid the mint action after a revocation.
    internal static var hasRegisteredIdentity: Bool {
      let credentials = CardCredentialStore.contents()
      return credentials.hasPin1
        && PrimeStore.storedCount() > 0
        && TKSmartCardTokenRegistrationManager.default.registeredSmartCardTokens
          .contains { CardTokenNamespace.owns(tokenIdentifier: $0) }
    }

    /// Whether the parent has either stored or complete entered credentials.
    internal let canPrepareCredentials: Bool

    /// Stores the two entries before opening the NFC field.
    internal let prepareCredentials: @MainActor () -> Bool

    /// Flipped when a hold ends with a registered identity.
    @Binding internal var isRegistered: Bool

    /// Owned by the parent, not by this view.
    ///
    /// The screen behind Apple's panel is cleared while a hold runs, and
    /// this view is part of what it clears. A run flag kept here would
    /// go out of the hierarchy with the view that sets it back, and the
    /// screen would stay empty for good -- which is exactly what
    /// happened when it was.
    internal let model: CardPrimingModel

    internal var body: some View {
      // The one primary action of the screen, so it is the one filled,
      // full-width control: the credential rows above collect, this
      // commits. Everything after the tap is Apple's NFC sheet.
      Button {
        Task {
          guard prepareCredentials() else { return }
          await model.prime()
          if case .succeeded = model.lastRunResult {
            isRegistered = true
          }
        }
      } label: {
        Text("Set identity")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier(actionIdentifier)
      .disabled(
        model.isRunning
          || !canPrepareCredentials
          || !model.allowsNearField
      )
      .onAppear {
        model.refresh()
      }
    }

    /// Lets the device test observe the completed operation without
    /// putting a diagnostic result row back into the holder's UI.
    private var actionIdentifier: String {
      switch model.lastRunResult {
      case .notRun, .succeeded:
        Self.startIdentifier
      case .failed:
        Self.failedIdentifier
      }
    }
  }

#endif
