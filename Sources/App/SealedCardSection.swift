#if os(macOS)

  import CardCore
  import SwiftUI

  /// The entry a sealed contactless card is waiting for.
  ///
  /// A card is present but no identity was published: a contactless
  /// card stays sealed until its printed access number opens it. The
  /// number is typed here, handed to the driver for this mint, and
  /// kept nowhere - there is no previously saved number to fall back
  /// on, and the entry leaves the window with this section.
  internal struct SealedCardSection: View {
    @State private var number = ""

    internal var body: some View {
      Section {
        SecureField("CAN, if the card is contactless", text: $number)
          .onChange(of: number) { _, typed in
            let digits = LimitedDigits.cardAccessNumber(typed)
            number = digits
            offerNumberToDriver(digits)
          }
          .accessibilityIdentifier("sealedCardAccessNumber")
        Text(
          """
          A contactless card answers only after its printed access \
          number is entered. It is used for this card and not kept.
          """
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }

    /// Takes the offered number back: at launch, and when the card leaves.
    ///
    /// It stays published while its card is present, because every
    /// contactless session - PIN management included - runs PACE again
    /// and needs it.
    internal static func withdrawOfferedNumber() {
      Task.detached(priority: .utility) {
        CardCredentialStore.withdrawCardAccessNumberFromDriver()
      }
    }

    /// Hands six just-typed digits to the driver and nudges the mint.
    ///
    /// Off the main actor: the configuration store is a synchronous
    /// call into `ctkd`, which must not block the window.
    private func offerNumberToDriver(_ digits: String) {
      guard digits.count == CardAccessNumber.digitCount else { return }
      Task.detached(priority: .utility) {
        CardCredentialStore.publishCardAccessNumberToDriver(digits: digits)
        await MainActor.run { LoginIdentityModel.shared.attemptRecovery() }
      }
    }
  }

#endif
