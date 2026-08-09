#if os(macOS)

  import CardCore
  import SwiftUI

  /// The card directory the Card menu opens: every card this device
  /// knows, each with its own CAN, and an Add flow that binds a typed
  /// CAN to the present card.
  ///
  /// Add asks the present card who it is: a contact insertion answers
  /// its serial freely, and a card on the antenna is unsealed with the
  /// typed CAN -- so a successful Add has proven the number against the
  /// card it binds to. The numbers are shown, not masked: they are
  /// printed on the card face, and they still never enter logs, traces
  /// or diagnostics exports.
  internal struct CardAccessNumberManagerView: View {
    /// Window identity, for the menu command that opens it.
    internal static let windowID = "card-access-number"

    /// The entry field's width, which grows with the text inside it.
    @ScaledMetric(relativeTo: .body)
    private var entryWidth: CGFloat = 120

    /// The window's own width, which grows with it.
    @ScaledMetric(relativeTo: .body)
    private var windowWidth: CGFloat = 440

    @State private var credentials = CardCredentialsModel()
    @State private var entry = ""
    @State private var reading = false

    /// Whether the entry is the six digits a CAN is.
    private var isEntryComplete: Bool {
      entry.count == CardAccessNumber.digitCount
    }

    internal var body: some View {
      Form {
        cardsSection
        addSection
      }
      .formStyle(.grouped)
      .frame(width: windowWidth)
      .onAppear { credentials.refresh() }
    }

    /// Every known card: model, serial, CAN, and a Delete.
    @ViewBuilder private var cardsSection: some View {
      Section("Cards") {
        if credentials.cards.isEmpty {
          Text("No cards yet. Put a card on the reader, enter its CAN below, and press Add.")
            .foregroundStyle(.secondary)
        }
        ForEach(credentials.cards, id: \.serial) { card in
          cardRow(card)
        }
        if let stored = credentials.storedCardAccessNumber {
          unknownCardRow(stored)
        }
      }
    }

    /// A CAN in, Add proves it against the present card and binds them.
    @ViewBuilder private var addSection: some View {
      Section("Add card") {
        LabeledContent("CAN") {
          HStack {
            TextField("CAN", text: $entry)
              .onChange(of: entry) { _, typed in
                entry = LimitedDigits.cardAccessNumber(typed)
              }
              .labelsHidden()
              .monospacedDigit()
              .frame(width: entryWidth)
              .onSubmit { add() }
              .accessibilityIdentifier("managerCardAccessNumberField")
            Button("Add") { add() }
              .disabled(!isEntryComplete || reading)
              .accessibilityIdentifier("managerAddCard")
          }
        }
        if reading {
          Text("Reading the card…")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if let failure = credentials.failure {
          Text(failure)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
    }

    /// One directory entry.
    @ViewBuilder
    private func cardRow(_ card: CardDirectory.Entry) -> some View {
      LabeledContent(card.model) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .trailing) {
            Text(card.can)
              .monospacedDigit()
            Text(card.serial)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .textSelection(.enabled)
          Button("Delete") { credentials.removeCard(serial: card.serial) }
            .accessibilityIdentifier("managerDeleteCard")
        }
      }
    }

    /// A number older builds stored without a card, kept until deleted
    /// or superseded by a proper add of the same digits.
    @ViewBuilder
    private func unknownCardRow(_ stored: String) -> some View {
      LabeledContent("Unknown card") {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .trailing) {
            Text(stored)
              .monospacedDigit()
            Text("not bound; tried after the cards above")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .textSelection(.enabled)
          Button("Delete") { credentials.forgetCardAccessNumber() }
            .accessibilityIdentifier("managerForgetCardAccessNumber")
        }
      }
    }

    /// Reads the present card with the typed CAN and records the pair.
    private func add() {
      guard isEntryComplete, !reading else { return }
      reading = true
      let digits = entry
      Task {
        if await credentials.addCard(proving: digits) {
          entry = ""
        }
        reading = false
      }
    }
  }

#endif
