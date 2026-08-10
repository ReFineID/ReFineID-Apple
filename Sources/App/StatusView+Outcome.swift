#if os(macOS)

  import AppKit
  import SwiftUI

  /// What the window says once signing has an answer.
  extension StatusView {
    /// Vertical gap inside the outcome stack.
    internal static let noticeSpacing: CGFloat = 4

    /// The success as a sentence, so what is spoken is what is shown
    /// rather than a bare file name.
    internal var signedOutcome: String? {
      guard let signed = signingModel.signed else { return nil }
      return String(localized: "Signed: \(signed.lastPathComponent)")
    }

    /// Progress, failure, or where the file went.
    @ViewBuilder internal var outcomeSection: some View {
      if signingModel.working || signingModel.failure != nil || signingModel.signed != nil {
        Section {
          if let failure = signingModel.failure {
            Text(failure)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
          if let note = signingModel.notice {
            Text(note)
              .foregroundStyle(.orange)
              .textSelection(.enabled)
          }
          if let signed = signingModel.signed {
            VStack(alignment: .leading, spacing: Self.noticeSpacing) {
              Text("Signed: \(signed.lastPathComponent)")
                .foregroundStyle(.green)
                .textSelection(.enabled)
              Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([signed])
              }
              .buttonStyle(.link)
            }
          }
        }
      }
    }
  }

#endif
