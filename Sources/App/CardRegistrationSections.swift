// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import CryptoTokenKit
  import SwiftUI

  /// The single identity-creation action embedded below both credentials,
  /// named for what it does: the certificate is read off the card over
  /// PACE and stored, and that stored read is the identity.
  ///
  /// Apple's NFC sheets own live progress and completion. Persistent card
  /// and Safari state belongs in Diagnostics, not below this button. The
  /// parent owns ``isRegistered``: a stored identity replaces this whole
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
        && !PrimeStore.primedHolderNames().isEmpty
        && TKSmartCardTokenRegistrationManager.default.registeredSmartCardTokens
          .contains { CardTokenNamespace.owns(tokenIdentifier: $0) }
    }

    /// Whether the parent has either stored or complete entered credentials.
    internal let canPrepareCredentials: Bool

    /// Whether this hold demonstrates the flow instead of reading a card.
    ///
    /// A demonstration keeps the button and the sheet and replaces what
    /// is behind them. ``DemoMode`` owns the identity it produces, so
    /// ``isRegistered`` stays about the card and is left alone.
    internal let isDemonstration: Bool

    /// Supplies the transient PIN to the one NFC operation.
    internal let enteredPin1: @MainActor () -> String?

    /// Commits PIN1 only after the card accepted it.
    internal let storeVerifiedPin1: @MainActor (String) -> Bool

    /// Clears the transient entry after the operation ends.
    internal let clearPin1Entry: @MainActor () -> Void

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

    /// Runs the one credential-registration path used by both initial setup
    /// and the later explicit certificate-read action.
    ///
    /// PIN1 remains transient until the card accepts it and Safari identity
    /// publication succeeds. Every outcome clears the entered value.
    @MainActor
    internal static func registerIdentity(
      pin1: String,
      model: CardPrimingModel,
      storeVerifiedPin1: @MainActor (String) -> Bool,
      clearPin1Entry: @MainActor () -> Void,
      markRegistered: @MainActor () -> Void
    ) async {
      defer { clearPin1Entry() }
      await model.prime(pin1: pin1)
      if case .succeeded = model.lastRunResult,
        storeVerifiedPin1(pin1)
      {
        markRegistered()
      }
    }

    internal var body: some View {
      // The one primary action of the screen, so it is the one filled,
      // full-width control: the credential rows above collect, this
      // commits. Everything after the tap is Apple's NFC sheet.
      Button {
        Task { @MainActor in
          guard let pin1 = enteredPin1() else { return }
          await Self.registerIdentity(
            pin1: pin1,
            model: model,
            storeVerifiedPin1: storeVerifiedPin1,
            clearPin1Entry: clearPin1Entry,
            markRegistered: { isRegistered = true })
        }
      } label: {
        Text("Read Certificate from Card")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier(actionIdentifier)
      .disabled(
        model.isRunning
          || !canPrepareCredentials
          || !isTransportReady
      )
      .onAppear {
        model.refresh()
      }
    }

    /// Whether this device can carry out the hold the button starts.
    ///
    /// A demonstration opens no slot it depends on, so an iPad's missing
    /// antenna is no reason to withhold the button from one.
    private var isTransportReady: Bool {
      model.allowsNearField || isDemonstration
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
