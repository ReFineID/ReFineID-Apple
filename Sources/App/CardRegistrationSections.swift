#if canImport(CoreNFC) && os(iOS)

  import CryptoTokenKit
  import SwiftUI

  /// The single identity-creation action embedded below both credentials.
  ///
  /// Apple's NFC sheets own live progress and completion. Persistent card
  /// and Safari state belongs in Diagnostics, not below this button.
  @available(iOS 26.0, *)
  internal struct CardRegistrationSections: View {
    /// Stable automation names; changing one never changes visible copy.
    private static let startIdentifier = "primeStartButton"
    private static let failedIdentifier = "primeFailed"
    private static let tokenPrefix = "fi.refineid.ReFineID.ctk:"

    /// Persistent system registration, read without waking NFC.
    private static var hasRegisteredIdentity: Bool {
      TKSmartCardTokenRegistrationManager.default.registeredSmartCardTokens
        .contains { $0.hasPrefix(Self.tokenPrefix) }
    }

    /// Whether the parent has either stored or complete entered credentials.
    internal let canPrepareCredentials: Bool

    /// Stores the two entries before opening the NFC field.
    internal let prepareCredentials: @MainActor () async -> Bool

    @State private var model = CardPrimingModel()
    @State private var isRegistered = false

    internal var body: some View {
      Group {
        if !isRegistered {
          Button("Mint identity token") {
            Task {
              guard await prepareCredentials() else { return }
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
