#if os(macOS)

  import CardCore
  import SwiftUI

  /// The activation form: the entry from the issuance letter, the two
  /// new PINs, and an explicit reactivation override.
  ///
  /// Which entry the card expects - the eight-digit activation code
  /// or the seven-digit activation PIN - depends on when it was
  /// issued; the driver classifies the card and refuses a wrong-length
  /// entry before anything is spent.
  internal struct CardActivationSection: View {
    internal let model: CardManagementModel

    @State private var entry = ""
    @State private var newPin1 = ""
    @State private var newPin1Repeated = ""
    @State private var newPin2 = ""
    @State private var newPin2Repeated = ""
    @State private var allowReactivation = false

    /// Ready when every entry can possibly be right; the exact
    /// activation-entry length is the card's to judge.
    private var isComplete: Bool {
      (Puk.minimumDigitCount...Puk.maximumDigitCount).contains(entry.count)
        && (Pin1.minimumDigitCount...Pin1.maximumDigitCount).contains(newPin1.count)
        && newPin1 == newPin1Repeated
        && (Pin2.minimumDigitCount...Pin2.maximumDigitCount).contains(newPin2.count)
        && newPin2 == newPin2Repeated
    }

    internal var body: some View {
      Section("Activate the card") {
        Text(
          "For a new card: enter the activation code or activation PIN "
            + "from the issuance letter, and choose both PINs."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        entryRows
        Toggle("Allow reactivation", isOn: $allowReactivation)
          .accessibilityIdentifier("managementActivationOverride")
        Button("Activate") {
          activate()
        }
        .disabled(!isComplete || model.working)
        .accessibilityIdentifier("managementActivate")
      }
    }

    /// The five secret fields.
    @ViewBuilder private var entryRows: some View {
      SecureField("Activation code or PIN", text: $entry)
        .onChange(of: entry) { _, typed in
          entry = LimitedDigits.puk(typed)
        }
        .accessibilityIdentifier("managementActivationEntry")
      SecureField("New PIN1", text: $newPin1)
        .onChange(of: newPin1) { _, typed in
          newPin1 = LimitedDigits.pin(typed)
        }
        .accessibilityIdentifier("managementActivationPin1")
      SecureField("New PIN1 again", text: $newPin1Repeated)
        .onChange(of: newPin1Repeated) { _, typed in
          newPin1Repeated = LimitedDigits.pin(typed)
        }
        .accessibilityIdentifier("managementActivationPin1Repeat")
      SecureField("New PIN2", text: $newPin2)
        .onChange(of: newPin2) { _, typed in
          newPin2 = LimitedDigits.pin(typed)
        }
        .accessibilityIdentifier("managementActivationPin2")
      SecureField("New PIN2 again", text: $newPin2Repeated)
        .onChange(of: newPin2Repeated) { _, typed in
          newPin2Repeated = LimitedDigits.pin(typed)
        }
        .accessibilityIdentifier("managementActivationPin2Repeat")
    }

    /// Runs activation and clears the fields when both PINs were set.
    private func activate() {
      guard isComplete, !model.working else { return }
      let activationEntry = entry
      let pin1Entry = newPin1
      let pin2Entry = newPin2
      let override = allowReactivation
      Task {
        let accepted = await model.activate(
          entry: activationEntry,
          newPin1: pin1Entry,
          newPin2: pin2Entry,
          allowReactivation: override
        )
        if accepted {
          entry = ""
          newPin1 = ""
          newPin1Repeated = ""
          newPin2 = ""
          newPin2Repeated = ""
          allowReactivation = false
        }
      }
    }
  }

#endif
