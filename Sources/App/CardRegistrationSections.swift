#if canImport(CoreNFC) && os(iOS)

  import CardCore
  import CryptoTokenKit
  import SwiftUI

  /// The single identity-creation action embedded below both credentials,
  /// replaced by a plain checkmark row once the identity exists.
  ///
  /// Apple's NFC sheets own live progress and completion. Persistent card
  /// and Safari state belongs in Diagnostics, not below this button.
  @available(iOS 26.0, *)
  internal struct CardRegistrationSections: View {
    /// Stable automation names; changing one never changes visible copy.
    private static let startIdentifier = "primeStartButton"
    private static let failedIdentifier = "primeFailed"
    private static let identityIdentifier = "identityStatus"
    /// Complete persistent identity state, read without waking NFC.
    ///
    /// A registration without its prime or stored PIN cannot sign. Treating
    /// that stale index as ready hid the mint action after a revocation.
    private static var hasRegisteredIdentity: Bool {
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

    @State private var model = CardPrimingModel()
    @State private var isRegistered = false

    internal var body: some View {
      Group {
        if isRegistered {
          // The finished state says one word and shows one mark, in the
          // same shape as the credential rows above it. Everything else
          // a holder can do from here is the forget action below.
          LabeledContent("Identity") {
            Image(systemName: "checkmark")
              .foregroundStyle(.green)
              .accessibilityLabel("Set")
          }
          .accessibilityIdentifier(Self.identityIdentifier)
        } else {
          Button("Mint identity token") {
            Task {
              guard prepareCredentials() else { return }
              await model.prime()
              if case .succeeded = model.lastRunResult {
                isRegistered = true
              }
            }
          }
          .accessibilityIdentifier(actionIdentifier)
          .disabled(
            model.isRunning
              || !canPrepareCredentials
              || !model.allowsNearField
          )
        }
      }
      .onAppear {
        model.refresh()
        isRegistered = Self.hasRegisteredIdentity
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
