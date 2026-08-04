#if os(macOS)

  import CardCore
  import SwiftUI

  /// The card-management window: attempts remaining, PIN changes, PUK
  /// unblock, and activation, all against the present card.
  ///
  /// Every operation probes the relevant retry counter first and
  /// refuses below the floor - the card's counters are the real access
  /// control, and this window never spends a near-last attempt. Entries
  /// are never stored and never echoed anywhere.
  internal struct CardManagementView: View {
    /// Window identity, for the menu command that opens it.
    internal static let windowID = "card-management"

    private static let windowWidth: CGFloat = 460

    @State private var model = CardManagementModel()

    internal var body: some View {
      Form {
        attemptsSection
        CredentialChangeSection(
          model: model,
          credential: .pin1
        )
        CredentialChangeSection(
          model: model,
          credential: .pin2
        )
        CredentialUnblockSection(model: model)
        CardActivationSection(model: model)
        outcomeSection
      }
      .formStyle(.grouped)
      .frame(width: Self.windowWidth)
      .task { await model.refresh() }
    }

    /// The counter-safe reading of all three credentials.
    @ViewBuilder private var attemptsSection: some View {
      Section("Attempts remaining") {
        LabeledContent("PIN1", value: Self.attempts(model.report?.pin1))
        LabeledContent("PIN2", value: Self.attempts(model.report?.pin2))
        LabeledContent("PUK", value: Self.attempts(model.report?.puk))
        Button("Refresh") {
          Task { await model.refresh() }
        }
        .disabled(model.working)
        .accessibilityIdentifier("managementRefresh")
      }
    }

    /// The one place outcomes are shown.
    @ViewBuilder private var outcomeSection: some View {
      if model.working || model.failure != nil || model.notice != nil {
        Section {
          if model.working {
            Text("Talking to the card...")
              .foregroundStyle(.secondary)
          }
          if let failure = model.failure {
            Text(failure)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
          if let notice = model.notice {
            Text(notice)
              .foregroundStyle(.green)
              .textSelection(.enabled)
          }
        }
      }
    }

    /// One probe outcome as a short cell.
    private static func attempts(_ outcome: RetryProbeOutcome?) -> String {
      switch outcome {
      case .remaining(let count):
        String(count.attemptsRemaining)
      case .verified:
        String(localized: "verified")
      case .locked:
        String(localized: "blocked")
      case .invalidated:
        String(localized: "invalidated")
      case .noInformation, .other:
        String(localized: "unknown")
      case .none:
        String(localized: "no card")
      }
    }
  }

#endif
