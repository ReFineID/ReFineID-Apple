#if os(macOS)

  import CardCore
  import SwiftUI

  /// The entry a sealed contactless card is waiting for.
  ///
  /// A card is present but no identity was published: a contactless
  /// card stays sealed until its printed access number opens it.
  /// Typing stays in the window - nothing reaches the driver or the
  /// card until the number is confirmed, because the card slows down
  /// after refused attempts and a half-typed or mistyped number must
  /// not spend one. The confirmed number is handed to the driver for
  /// this mint and kept nowhere - there is no previously saved number
  /// to fall back on, and the entry leaves the window with this
  /// section.
  internal struct SealedCardSection: View {
    @State private var number = ""

    /// Whether the typed digits are a whole access number.
    private var isComplete: Bool {
      number.count == CardAccessNumber.digitCount
    }

    internal var body: some View {
      Section {
        SecureField("CAN, if the card is contactless", text: $number)
          .onChange(of: number) { _, typed in
            number = LimitedDigits.cardAccessNumber(typed)
          }
          .onSubmit(confirm)
          .accessibilityIdentifier("sealedCardAccessNumber")
        Text(
          """
          A contactless card answers only after its printed access \
          number is entered. It is sent to the card once, when \
          confirmed, and not kept.
          """
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        HStack {
          Spacer()
          Button("Confirm", action: confirm)
            .disabled(!isComplete)
            .accessibilityIdentifier("sealedCardAccessNumberConfirm")
        }
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

    /// Hands the confirmed number to the driver and asks for the mint.
    ///
    /// The driver tries it once: a refused number is remembered by
    /// fingerprint and not tried again while the card stays on the
    /// antenna, and confirming a different number is what earns the
    /// card a fresh attempt.
    ///
    /// Off the main actor: the configuration store is a synchronous
    /// call into `ctkd`, which must not block the window.
    private func confirm() {
      guard isComplete else { return }
      let digits = number
      Task.detached(priority: .utility) {
        CardCredentialStore.publishCardAccessNumberToDriver(digits: digits)
        await MainActor.run { LoginIdentityModel.shared.retryWithConfirmedNumber() }
      }
    }
  }

#endif
