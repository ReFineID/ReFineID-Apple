#if os(macOS)

  import SwiftUI

  /// The card access number, and what it unlocked.
  ///
  /// The number is the whole of the setting: give one and the document
  /// is stamped with the handwritten signature the card carries, leave
  /// it empty and it is not. Nothing is remembered - the number
  /// unlocks reading the card, so storing it would be keeping a key to
  /// the holder's own card for no reason.
  internal struct StampRow: View {
    private static let entryWidth: CGFloat = 90
    private static let previewHeight: CGFloat = 44
    private static let spacing: CGFloat = 6

    /// How long the number rests before the card is read, so a
    /// six-digit entry is not six trips to the card.
    private static let restDelay: Duration = .seconds(1)

    /// The signing state the number reads into.
    internal let signing: SignDocumentModel

    /// The number as typed.
    @Binding internal var accessNumber: String

    internal var body: some View {
      LabeledContent("Stamp with CAN") {
        HStack(spacing: Self.spacing) {
          if signing.readingStamp {
            ProgressView().controlSize(.small)
          }
          TextField("optional", text: $accessNumber)
            .frame(width: Self.entryWidth)
            .multilineTextAlignment(.trailing)
            .onChange(of: accessNumber) { _, typed in
              accessNumber = LimitedDigits.cardAccessNumber(typed)
            }
            .accessibilityIdentifier("signAccessNumber")
        }
      }
      .task(id: accessNumber) {
        try? await Task.sleep(for: Self.restDelay)
        guard !Task.isCancelled else { return }
        await signing.readStamp(accessNumber: accessNumber)
      }
      if let stamp = signing.stamp {
        StampPreview(artwork: stamp)
          .frame(height: Self.previewHeight)
          .accessibilityLabel("The signature that will be stamped")
      }
      if let note = signing.stampFailure {
        Text(note)
          .foregroundStyle(.orange)
          .font(.footnote)
      }
    }
  }

#endif
