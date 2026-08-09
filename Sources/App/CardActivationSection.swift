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
    /// The keyboard path through the section.
    private enum Field {
      case entry
      case pin1
      case pin1Repeat
      case pin2
      case pin2Repeat
    }

    internal let model: CardManagementModel

    @State private var entry = ""
    @State private var newPin1 = ""
    @State private var newPin1Repeated = ""
    @State private var newPin2 = ""
    @State private var newPin2Repeated = ""
    @State private var allowReactivation = false
    @State private var pending: CredentialOperationConfirmation.Operation?
    @FocusState private var focus: Field?

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
      Section {
        Text(
          "For a new card: enter the activation code or activation PIN "
            + "from the issuance letter, and choose both PINs."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        entryRows
        Toggle("Allow reactivation", isOn: $allowReactivation)
          .accessibilityIdentifier("managementActivationOverride")
        HStack {
          Spacer()
          Button("Activate") {
            pending = .activate
          }
          .buttonStyle(.borderedProminent)
          .disabled(!isComplete || model.working)
          .accessibilityIdentifier("managementActivate")
        }
      }
      .task {
        // This form never placed focus at all, so its first field had
        // to be found with a pointer. See InitialFieldFocus for why the
        // window is allowed to settle first.
        await InitialFieldFocus.settle()
        focus = .entry
      }
      .confirmCredentialOperation($pending, report: model.report) { _ in
        activate()
      }
    }

    /// The five secret fields.
    @ViewBuilder private var entryRows: some View {
      SecureField("Activation code or PIN", text: $entry)
        .onChange(of: entry) { _, typed in
          entry = LimitedDigits.puk(typed)
        }
        .focused($focus, equals: .entry)
        .onSubmit { advance(from: .entry) }
        .accessibilityIdentifier("managementActivationEntry")
      SecureField("New PIN 1", text: $newPin1)
        .onChange(of: newPin1) { _, typed in
          newPin1 = LimitedDigits.pin(typed)
        }
        .focused($focus, equals: .pin1)
        .onSubmit { advance(from: .pin1) }
        .accessibilityIdentifier("managementActivationPin1")
      SecureField("New PIN 1 again", text: $newPin1Repeated)
        .onChange(of: newPin1Repeated) { _, typed in
          newPin1Repeated = LimitedDigits.pin(typed)
        }
        .focused($focus, equals: .pin1Repeat)
        .onSubmit { advance(from: .pin1Repeat) }
        .accessibilityIdentifier("managementActivationPin1Repeat")
      SecureField("New PIN 2", text: $newPin2)
        .onChange(of: newPin2) { _, typed in
          newPin2 = LimitedDigits.pin(typed)
        }
        .focused($focus, equals: .pin2)
        .onSubmit { advance(from: .pin2) }
        .accessibilityIdentifier("managementActivationPin2")
      SecureField("New PIN 2 again", text: $newPin2Repeated)
        .onChange(of: newPin2Repeated) { _, typed in
          newPin2Repeated = LimitedDigits.pin(typed)
        }
        .focused($focus, equals: .pin2Repeat)
        .onSubmit { advance(from: .pin2Repeat) }
        .accessibilityIdentifier("managementActivationPin2Repeat")
    }

    /// Return advances; on the last field it submits when complete.
    private func advance(from field: Field) {
      switch field {
      case .entry:
        focus = .pin1
      case .pin1:
        focus = .pin1Repeat
      case .pin1Repeat:
        focus = .pin2
      case .pin2:
        focus = .pin2Repeat
      case .pin2Repeat:
        // Return on the last field asks the same question the button
        // asks; the entry from the letter works once.
        if isComplete {
          pending = .activate
        }
      }
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
          focus = nil
        }
      }
    }
  }

#endif
