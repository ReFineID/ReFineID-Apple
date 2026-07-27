#if canImport(CoreNFC) && os(iOS)

  import SwiftUI

  /// Where the holder sets their card up for Safari, with one hold.
  ///
  /// The screen is honest about what the hold costs and what it buys: a
  /// few seconds of holding the card still now, in exchange for logins
  /// later that do not have to read the card all over again. Everything
  /// the card gives up here is public -- the certificate it shows every
  /// website, and its serial -- and the screen says so, because the
  /// holder is being asked to let this device remember something.
  @available(iOS 26.0, *)
  internal struct CardPrimingView: View {
    private static let noteSpacing: CGFloat = 4

    @State private var model = CardPrimingModel()

    internal var body: some View {
      Form {
        startSection
        if !model.notes.isEmpty {
          progressSection
        }
        if let outcome = model.outcome {
          outcomeSection(outcome)
        }
        if let failure = model.failure {
          Section {
            Text(failure)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Set up Safari login")
      .onAppear { model.refresh() }
    }

    /// The button, and what pressing it will ask of the holder.
    @ViewBuilder private var startSection: some View {
      Section {
        Button("Set up this card") {
          Task { await model.prime() }
        }
        .disabled(model.isRunning || !model.contents.hasCardAccessNumber || !model.allowsNearField)
        if model.isRunning {
          ProgressView()
        }
      } header: {
        Text("One hold")
      } footer: {
        Text(
          """
          Hold your card flat against the top of the phone and keep it \
          there until this screen says it is done. ReFineID reads the \
          certificate your card shows to websites, plus its serial \
          number, and remembers them on this iPhone so that later logins \
          do not have to read them again. Nothing secret leaves the card.
          """)
      }
    }

    /// What the run has done so far.
    @ViewBuilder private var progressSection: some View {
      Section {
        VStack(alignment: .leading, spacing: Self.noteSpacing) {
          ForEach(model.notes, id: \.self) { note in
            Text(note)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("Progress")
      }
    }

    /// How the run ended.
    @ViewBuilder
    private func outcomeSection(_ outcome: CardPriming.Outcome) -> some View {
      Section {
        Text(outcome.summary)
        LabeledContent(
          "Card details",
          value: outcome.stored
            ? String(localized: "Stored on this iPhone")
            : String(localized: "Not stored"))
        LabeledContent(
          "Safari",
          value: outcome.registered
            ? String(localized: "Can ask for this card")
            : String(localized: "Not set up"))
      } header: {
        Text("Result")
      }
    }
  }

#endif
