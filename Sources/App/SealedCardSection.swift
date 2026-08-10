#if os(macOS)

  import CardCore
  import SwiftUI

  /// The entry a sealed contactless card is waiting for.
  ///
  /// Shown only when the slot's answer proves the card is on the
  /// antenna, so the row needs no explaining - entering the printed
  /// access number is the one thing to do. Typing stays in the
  /// window: nothing reaches the driver or the card until the number
  /// is confirmed, because the card slows down after refused attempts
  /// and a half-typed or mistyped number must not spend one. The
  /// confirmed number is offered to the driver for this mint and kept
  /// nowhere - the offer leaves the window with this section.
  internal struct SealedCardSection: View {
    @State private var number = ""

    /// Whether the typed digits are a whole access number.
    private var isComplete: Bool {
      number.count == CardAccessNumber.digitCount
    }

    internal var body: some View {
      Section {
        HStack {
          SecureField("CAN", text: $number)
            .onChange(of: number) { _, typed in
              number = LimitedDigits.cardAccessNumber(typed)
            }
            .onSubmit(confirm)
            .accessibilityIdentifier("sealedCardAccessNumber")
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
    /// Off the main actor: the offer and the withdraw share their
    /// queue with calls into `ctkd`, which must not block the window.
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
