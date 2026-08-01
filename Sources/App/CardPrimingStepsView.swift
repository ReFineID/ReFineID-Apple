#if canImport(CoreNFC) && os(iOS)

  import SwiftUI

  /// How far the hold got, one row per step.
  ///
  /// This exists because the system NFC sheet cannot say. It has no
  /// failure state -- `TKSmartCardSlotNFCSession` offers a message and
  /// `endSession`, so it dismisses with a checkmark whether the identity
  /// was registered or the card slipped during PACE. A holder who saw
  /// that checkmark and no identity had no way to tell which step broke.
  ///
  /// The rows appear while a hold runs and stay afterwards, because the
  /// holder is looking at the card during the hold and at the screen
  /// after it.
  @available(iOS 26.0, *)
  internal struct CardPrimingStepsView: View {
    /// How far the failure sentence sits from the rows above it.
    private static let summarySpacing: CGFloat = 4

    /// How faint an unreached step's marker is.
    private static let waitingOpacity: Double = 0.4

    /// The model holding the running or finished states.
    internal let model: CardPrimingModel

    internal var body: some View {
      ForEach(CardPrimingStep.allCases, id: \.self) { step in
        row(step)
      }
      if let summary = model.summary, model.lastRunResult == .failed {
        Text(summary)
          .font(.footnote)
          .foregroundStyle(.red)
          .padding(.top, Self.summarySpacing)
          .accessibilityIdentifier("primeFailureSummary")
      }
    }

    /// What a marker means, for a holder who cannot see its colour.
    ///
    /// Colour alone is not a status: this is the same information in
    /// words, and it is what VoiceOver reads out.
    private static func spokenState(_ state: CardPrimingStep.State) -> String {
      switch state {
      case .done:
        String(localized: "Done")
      case .failed:
        String(localized: "Failed")
      case .running:
        String(localized: "Running")
      case .waiting:
        String(localized: "Waiting")
      }
    }

    /// One step, its marker, and what the marker means to VoiceOver.
    private func row(_ step: CardPrimingStep) -> some View {
      let state = model.state(of: step)
      return LabeledContent(step.title) {
        indicator(state)
      }
      .foregroundStyle(state == .waiting ? Color.secondary : Color.primary)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(step.title)
      .accessibilityValue(Self.spokenState(state))
    }

    /// The marker, or a spinner while the step is the one running.
    ///
    /// Each state carries a distinct SHAPE as well as a colour: a check
    /// for done, a cross for failed, an empty circle for not yet
    /// reached. Roughly one man in twelve cannot separate the green from
    /// the red, and a status they cannot read is not a status. The row
    /// above speaks the state, so the marker itself is hidden from
    /// accessibility rather than read twice.
    @ViewBuilder
    private func indicator(_ state: CardPrimingStep.State) -> some View {
      switch state {
      case .running:
        ProgressView()
      case .done:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Color.green)
          .accessibilityHidden(true)
      case .failed:
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(Color.red)
          .accessibilityHidden(true)
      case .waiting:
        Image(systemName: "circle")
          .foregroundStyle(Color.secondary.opacity(Self.waitingOpacity))
          .accessibilityHidden(true)
      }
    }
  }

#endif
