#if os(macOS)

  import CardCore
  import SwiftUI

  /// One PIN's change form: the current value, the new one twice, and
  /// a Change that stays disabled until the entries can possibly be
  /// right.
  internal struct CredentialChangeSection: View {
    /// Which PIN this section changes; only the two PINs change here.
    internal enum Credential {
      case pin1
      case pin2

      /// The on-screen name.
      internal var name: String {
        switch self {
        case .pin1:
          "PIN1"
        case .pin2:
          "PIN2"
        }
      }

      /// The entry bounds of this PIN.
      internal var digitBounds: ClosedRange<Int> {
        switch self {
        case .pin1:
          Pin1.minimumDigitCount...Pin1.maximumDigitCount
        case .pin2:
          Pin2.minimumDigitCount...Pin2.maximumDigitCount
        }
      }
    }

    internal let model: CardManagementModel
    internal let credential: Credential

    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""

    /// Ready when every entry is inside its bounds and the new value
    /// is typed identically twice.
    private var isComplete: Bool {
      credential.digitBounds.contains(current.count)
        && credential.digitBounds.contains(new.count)
        && new == repeated
    }

    internal var body: some View {
      Section {
        SecureField("Current \(credential.name)", text: $current)
          .onChange(of: current) { _, typed in
            current = LimitedDigits.pin(typed)
          }
          .accessibilityIdentifier("managementChange\(credential.name)Current")
        SecureField("New \(credential.name)", text: $new)
          .onChange(of: new) { _, typed in
            new = LimitedDigits.pin(typed)
          }
          .accessibilityIdentifier("managementChange\(credential.name)New")
        SecureField("New \(credential.name) again", text: $repeated)
          .onChange(of: repeated) { _, typed in
            repeated = LimitedDigits.pin(typed)
          }
          .accessibilityIdentifier("managementChange\(credential.name)Repeat")
        if !new.isEmpty, !repeated.isEmpty, new != repeated {
          Text("The new entries differ.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        HStack {
          Spacer()
          Button("Change \(credential.name)") {
            change()
          }
          .buttonStyle(.borderedProminent)
          .disabled(!isComplete || model.working)
          .accessibilityIdentifier("managementChange\(credential.name)")
        }
      }
    }

    /// Runs the change and clears the fields when the card accepted.
    private func change() {
      guard isComplete, !model.working else { return }
      let currentEntry = current
      let newEntry = new
      Task {
        let accepted =
          switch credential {
          case .pin1:
            await model.changePin1(current: currentEntry, new: newEntry)
          case .pin2:
            await model.changePin2(current: currentEntry, new: newEntry)
          }
        if accepted {
          current = ""
          new = ""
          repeated = ""
        }
      }
    }
  }

#endif
