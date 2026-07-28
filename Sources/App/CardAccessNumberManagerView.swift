#if os(macOS)

  import CardCore
  import SwiftUI

  /// The manager window the Card menu opens: see, replace, or forget the
  /// stored card access number, with no card required.
  ///
  /// The status row needs a sealed card to be readable before it appears,
  /// which is exactly when the reader is busiest -- so management lives
  /// here, available whenever the app runs. The number is shown, not
  /// masked: it is printed on the card face and exists to stop remote
  /// skimming, not to be hidden from its holder (decision 2026-07-28).
  /// It still never enters logs, traces or diagnostics exports.
  internal struct CardAccessNumberManagerView: View {
    /// Window identity, for the menu command that opens it.
    internal static let windowID = "card-access-number"

    private static let entryWidth: CGFloat = 120
    private static let windowWidth: CGFloat = 380

    @State private var credentials = CardCredentialsModel()
    @State private var entry = ""

    /// Whether the entry is the six digits a card access number is.
    private var isEntryComplete: Bool {
      entry.count == CardAccessNumber.digitCount
    }

    internal var body: some View {
      Form {
        storedRow
        entryRow
        forgetButton
        if let failure = credentials.failure {
          Text(failure)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
      .formStyle(.grouped)
      .frame(width: Self.windowWidth)
      .onAppear { credentials.refresh() }
    }

    /// The stored CAN, readable and selectable, or None.
    @ViewBuilder private var storedRow: some View {
      LabeledContent("Stored CAN") {
        Text(credentials.storedCardAccessNumber ?? String(localized: "None"))
          .monospacedDigit()
          .textSelection(.enabled)
          .accessibilityIdentifier("storedCardAccessNumber")
      }
    }

    /// Six digits in, Save when they are all there.
    ///
    /// The field starts empty: a placeholder that looks like a number
    /// reads as one.
    @ViewBuilder private var entryRow: some View {
      LabeledContent("New CAN") {
        HStack {
          TextField("CAN", text: $entry)
            .labelsHidden()
            .frame(width: Self.entryWidth)
            .onSubmit { save() }
            .accessibilityIdentifier("managerCardAccessNumberField")
          Button("Save") { save() }
            .disabled(!isEntryComplete)
            .accessibilityIdentifier("managerSaveCardAccessNumber")
        }
      }
    }

    /// Drops the stored number, in those words.
    @ViewBuilder private var forgetButton: some View {
      Button("Forget stored number") {
        credentials.forgetCardAccessNumber()
      }
      .disabled(credentials.storedCardAccessNumber == nil)
      .accessibilityIdentifier("managerForgetCardAccessNumber")
    }

    /// Stores the entry and clears it; the model reports any refusal.
    private func save() {
      guard isEntryComplete else { return }
      let digits = entry
      entry = ""
      credentials.saveCardAccessNumber(digits)
    }
  }

#endif
