#if os(macOS)

  import CardCore
  import SwiftUI

  /// The unblock form: which PIN to unblock, the PUK, and the new
  /// value twice.
  ///
  /// A wrong PUK spends the PUK itself and exhausting it is terminal
  /// for the card, which is why the driver holds the retry floor
  /// against the PUK's counter before anything is sent.
  internal struct CredentialUnblockSection: View {
    internal let model: CardManagementModel

    @State private var target: CredentialRole = .pin1
    @State private var puk = ""
    @State private var new = ""
    @State private var repeated = ""

    /// The entry bounds of the targeted PIN.
    private var targetBounds: ClosedRange<Int> {
      target == .pin2
        ? Pin2.minimumDigitCount...Pin2.maximumDigitCount
        : Pin1.minimumDigitCount...Pin1.maximumDigitCount
    }

    /// Ready when the PUK and both new entries can possibly be right.
    private var isComplete: Bool {
      (Puk.minimumDigitCount...Puk.maximumDigitCount).contains(puk.count)
        && targetBounds.contains(new.count)
        && new == repeated
    }

    internal var body: some View {
      Section {
        entryRows
        if !new.isEmpty, !repeated.isEmpty, new != repeated {
          Text("The new entries differ.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        HStack {
          Spacer()
          Button("Unblock") {
            unblock()
          }
          .buttonStyle(.borderedProminent)
          .disabled(!isComplete || model.working)
          .accessibilityIdentifier("managementUnblock")
        }
      }
    }

    /// The target picker and the three secret fields.
    @ViewBuilder private var entryRows: some View {
      Picker("PIN", selection: $target) {
        Text("PIN1").tag(CredentialRole.pin1)
        Text("PIN2").tag(CredentialRole.pin2)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("managementUnblockTarget")
      SecureField("PUK", text: $puk)
        .onChange(of: puk) { _, typed in
          puk = LimitedDigits.puk(typed)
        }
        .accessibilityIdentifier("managementUnblockPuk")
      SecureField("New PIN", text: $new)
        .onChange(of: new) { _, typed in
          new = LimitedDigits.pin(typed)
        }
        .accessibilityIdentifier("managementUnblockNew")
      SecureField("New PIN again", text: $repeated)
        .onChange(of: repeated) { _, typed in
          repeated = LimitedDigits.pin(typed)
        }
        .accessibilityIdentifier("managementUnblockRepeat")
    }

    /// Runs the unblock and clears the fields when the card accepted.
    private func unblock() {
      guard isComplete, !model.working else { return }
      let unblockTarget = target
      let pukEntry = puk
      let newEntry = new
      Task {
        if await model.unblock(target: unblockTarget, puk: pukEntry, new: newEntry) {
          puk = ""
          new = ""
          repeated = ""
        }
      }
    }
  }

#endif
