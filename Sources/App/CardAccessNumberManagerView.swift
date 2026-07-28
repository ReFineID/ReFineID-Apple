#if os(macOS)

  import CardCore
  import SwiftUI

  /// The manager window the Card menu opens: one CAN, the card it
  /// belongs to, and Save / Forget.
  ///
  /// The CAN field holds the stored number and is edited in place. The
  /// serial row says which card the number is bound to -- from the
  /// stored binding, or read live from a present card that answers
  /// without a number (a contact insertion does; a sealed antenna
  /// offers nothing card-unique before PACE, by design). Saving while a
  /// card's serial is readable binds the number to that card. The
  /// number is shown, not masked: it is printed on the card face, and
  /// it still never enters logs, traces or diagnostics exports.
  internal struct CardAccessNumberManagerView: View {
    /// Window identity, for the menu command that opens it.
    internal static let windowID = "card-access-number"

    private static let entryWidth: CGFloat = 120
    private static let windowWidth: CGFloat = 380

    @State private var credentials = CardCredentialsModel()
    @State private var entry = ""

    /// The present card's serial, when it answered one without a CAN.
    @State private var liveSerial: TokenSerial?

    /// Whether the entry is the six digits a CAN is.
    private var isEntryComplete: Bool {
      entry.count == CardAccessNumber.digitCount
    }

    /// The bound serial first: that is the recorded fact.
    ///
    /// A live read stands in for it until a save binds one.
    private var serialText: String {
      credentials.storedBoundSerial ?? liveSerial?.value ?? String(localized: "None")
    }

    internal var body: some View {
      Form {
        canRow
        serialRow
        actionRow
        if let failure = credentials.failure {
          Text(failure)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
      .formStyle(.grouped)
      .frame(width: Self.windowWidth)
      .onAppear { load() }
    }

    /// The one number, edited in place.
    @ViewBuilder private var canRow: some View {
      LabeledContent("CAN") {
        TextField("CAN", text: $entry)
          .labelsHidden()
          .monospacedDigit()
          .frame(width: Self.entryWidth)
          .onSubmit { save() }
          .accessibilityIdentifier("managerCardAccessNumberField")
      }
    }

    /// The card the number belongs to, when anything can say.
    @ViewBuilder private var serialRow: some View {
      LabeledContent("Card serial") {
        Text(serialText)
          .monospacedDigit()
          .textSelection(.enabled)
          .accessibilityIdentifier("managerCardSerial")
      }
    }

    /// Save and Forget, in those words.
    @ViewBuilder private var actionRow: some View {
      HStack {
        Button("Save") { save() }
          .disabled(!isEntryComplete)
          .accessibilityIdentifier("managerSaveCardAccessNumber")
        Button("Forget") { forget() }
          .disabled(credentials.storedCardAccessNumber == nil)
          .accessibilityIdentifier("managerForgetCardAccessNumber")
      }
    }

    /// Seeds the field from the store and asks a present card its serial.
    private func load() {
      credentials.refresh()
      entry = credentials.storedCardAccessNumber ?? ""
      Task {
        liveSerial = await CardSerialProbe.read()
      }
    }

    /// Stores the entry, bound to the present card when one answered.
    private func save() {
      guard isEntryComplete else { return }
      credentials.saveCardAccessNumber(entry, boundToSerial: liveSerial?.value)
    }

    /// Drops the stored number, its binding, and the field.
    private func forget() {
      credentials.forgetCardAccessNumber()
      entry = ""
    }
  }

#endif
