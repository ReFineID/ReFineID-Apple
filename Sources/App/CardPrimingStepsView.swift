import SwiftUI

/// The setup steps as a row of lights.
///
/// A holder pressing a card against a phone cannot see whether anything
/// is happening. One light per step, filling in as they pass, turns
/// several silent seconds into visible progress -- and when a hold is
/// broken half way the light that was running goes red, so the holder is
/// told which part did not survive rather than only that setup failed.
internal struct CardPrimingStepsView: View {
  private static let lightSize: CGFloat = 14
  private static let rowSpacing: CGFloat = 10

  /// How much larger a filled symbol is drawn than a stroked circle.
  ///
  /// A filled glyph reads smaller than an outline of the same size, so
  /// the finished and failed lights are nudged up to sit level with the
  /// ones still waiting.
  private static let symbolInset: CGFloat = 2

  /// The size the finished and failed glyphs are drawn at.
  private static let symbolSize: CGFloat = lightSize + symbolInset

  /// Stroke width of a light that has not been reached yet.
  private static let outlineWidth: CGFloat = 1.5

  /// The state of every step, in the order they happen.
  internal let states: [CardPrimingStep: CardPrimingStep.State]

  internal var body: some View {
    VStack(alignment: .leading, spacing: Self.rowSpacing) {
      ForEach(CardPrimingStep.allCases, id: \.rawValue) { step in
        let state = states[step] ?? .waiting
        HStack(spacing: Self.rowSpacing) {
          light(for: state)
          Text(step.title)
            .foregroundStyle(state == .waiting ? .secondary : .primary)
          Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.description(of: step, in: state))
      }
    }
  }

  /// What a screen reader says for one step.
  private static func description(
    of step: CardPrimingStep, in state: CardPrimingStep.State
  ) -> String {
    switch state {
    case .done:
      String(localized: "\(step.title): done")
    case .failed:
      String(localized: "\(step.title): failed")
    case .running:
      String(localized: "\(step.title): in progress")
    case .waiting:
      String(localized: "\(step.title): waiting")
    }
  }

  /// The light itself: filled once reached, hollow while waiting.
  ///
  /// A running step spins rather than sitting still, because a still
  /// light and a stuck one look identical and only one of them means
  /// keep holding.
  @ViewBuilder
  private func light(for state: CardPrimingStep.State) -> some View {
    switch state {
    case .waiting:
      Circle()
        .strokeBorder(.secondary, lineWidth: Self.outlineWidth)
        .frame(width: Self.lightSize, height: Self.lightSize)
    case .running:
      ProgressView()
        .controlSize(.small)
        .frame(width: Self.lightSize, height: Self.lightSize)
    case .done:
      Image(systemName: "checkmark.circle.fill")
        .accessibilityHidden(true)
        .foregroundStyle(.green)
        .font(.system(size: Self.symbolSize))
    case .failed:
      Image(systemName: "xmark.circle.fill")
        .accessibilityHidden(true)
        .foregroundStyle(.red)
        .font(.system(size: Self.symbolSize))
    }
  }
}
