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

    private static let entryWidth: CGFloat = 120
    private static let windowWidth: CGFloat = 440

    @State private var credentials = CardCredentialsModel()
    @State private var entry = ""
    @State private var reading = false
    @State private var note: String?

    /// Whether the entry is the six digits a CAN is.
    private var isEntryComplete: Bool {
      entry.count == CardAccessNumber.digitCount
    }

    internal var body: some View {
      Form {
        cardsSection
        addSection
        unboundSection
      }
      .formStyle(.grouped)
      .frame(width: Self.windowWidth)
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
      }
    }

    /// A CAN in, Add proves it against the present card and binds them.
    @ViewBuilder private var addSection: some View {
      Section("Add card") {
        LabeledContent("CAN") {
          HStack {
            TextField("CAN", text: $entry)
              .labelsHidden()
              .monospacedDigit()
              .frame(width: Self.entryWidth)
              .onSubmit { add() }
              .accessibilityIdentifier("managerCardAccessNumberField")
            Button("Add") { add() }
              .disabled(!isEntryComplete || reading)
              .accessibilityIdentifier("managerAddCard")
          }
        }
        if reading {
          Text("Reading the card...")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if let note {
          Text(note)
            .font(.footnote)
            .foregroundStyle(.red)
        }
        if let failure = credentials.failure {
          Text(failure)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
    }

    /// The single number older builds stored: unbound, tried after the
    /// directory, forgettable in one word.
    @ViewBuilder private var unboundSection: some View {
      if let stored = credentials.storedCardAccessNumber {
        Section("Unbound number") {
          LabeledContent("CAN") {
            HStack {
              Text(stored)
                .monospacedDigit()
                .textSelection(.enabled)
              Button("Forget") { credentials.forgetCardAccessNumber() }
                .accessibilityIdentifier("managerForgetCardAccessNumber")
            }
          }
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

    /// Reads the present card with the typed CAN and records the pair.
    private func add() {
      guard isEntryComplete, !reading else { return }
      reading = true
      note = nil
      let digits = entry
      Task {
        let answer = await CardSerialProbe.read(unsealingWith: digits)
        reading = false
        guard let answer else {
          note = String(
            localized: """
              No card answered. The contact slot reads directly; a card on \
              the antenna answers only its own CAN.
              """)
          return
        }
        credentials.addCard(
          can: digits,
          serial: answer.serial.value,
          modelKey: answer.modelKey,
          model: answer.model
        )
        entry = ""
      }
    }
  }

#endif
