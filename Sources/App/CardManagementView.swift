#if os(macOS)

  import CardCore
  import SwiftUI

  /// The card-management window: attempts remaining at a glance, and
  /// one management task at a time.
  ///
  /// The window reads the card's state and leads with what the card
  /// needs: a blocked PIN opens on Unblock, a healthy card on a PIN
  /// change; activation is there when asked for, not permanently on
  /// screen. Every operation probes the relevant retry counter first
  /// and refuses below the floor - the card's counters are the real
  /// access control, and this window never spends a near-last attempt.
  /// Entries are never stored and never echoed anywhere.
  internal struct CardManagementView: View {
    /// The one management task shown at a time.
    internal enum ManagementTask: CaseIterable, Identifiable {
      case changePin1
      case changePin2
      case unblock
      case activate

      internal var id: Self { self }

      /// The on-screen name.
      internal var name: String {
        switch self {
        case .changePin1:
          String(localized: "Change PIN1")
        case .changePin2:
          String(localized: "Change PIN2")
        case .unblock:
          String(localized: "Unblock a PIN")
        case .activate:
          String(localized: "Activate the card")
        }
      }
    }

    /// Window identity, for the menu command that opens it.
    internal static let windowID = "card-management"

    private static let windowWidth: CGFloat = 460

    private static let rowSymbolSpacing: CGFloat = 6

    @State private var model = CardManagementModel()
    @State private var task: ManagementTask = .changePin1
    @State private var hasChosenTask = false

    internal var body: some View {
      Form {
        attemptsSection
        taskSection
        outcomeSection
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.windowWidth)
      .toolbar {
        Button("Refresh", systemImage: "arrow.clockwise") {
          Task { await model.refresh() }
        }
        .help("Read the attempt counters again")
        .keyboardShortcut("r", modifiers: .command)
        .disabled(model.working)
        .accessibilityIdentifier("managementRefresh")
      }
      .task { await model.refresh() }
      .onChange(of: model.report) { _, report in
        suggestTask(from: report)
      }
      .onChange(of: model.failure) { _, failure in
        announce(failure)
      }
      .onChange(of: model.notice) { _, notice in
        announce(notice)
      }
    }

    /// The counter-safe reading of all three credentials, colored by
    /// how close each is to the edge.
    @ViewBuilder private var attemptsSection: some View {
      Section("Attempts remaining") {
        attemptsRow("PIN1", model.report?.pin1)
        attemptsRow("PIN2", model.report?.pin2)
        attemptsRow("PUK", model.report?.puk)
      }
    }

    /// The chosen task, and only it.
    @ViewBuilder private var taskSection: some View {
      Section {
        Picker("Task", selection: $task) {
          ForEach(ManagementTask.allCases) { candidate in
            Text(candidate.name).tag(candidate)
          }
        }
        .pickerStyle(.menu)
        .disabled(model.working)
        .accessibilityIdentifier("managementTask")
        .onChange(of: task) { _, _ in
          hasChosenTask = true
        }
      }
      switch task {
      case .changePin1:
        CredentialChangeSection(model: model, credential: .pin1)
      case .changePin2:
        CredentialChangeSection(model: model, credential: .pin2)
      case .unblock:
        CredentialUnblockSection(model: model)
      case .activate:
        CardActivationSection(model: model)
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

    /// The color-independent state marker beside each count.
    private static func attemptsSymbol(_ outcome: RetryProbeOutcome?) -> String {
      switch outcome {
      case .remaining(let count):
        count.isBlocked
          ? "xmark.octagon.fill"
          : count.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
      case .verified:
        "checkmark.circle.fill"
      case .locked, .invalidated:
        "xmark.octagon.fill"
      case .noInformation, .other, .none:
        "questionmark.circle"
      }
    }

    /// What VoiceOver says for one reading.
    private static func attemptsSpoken(_ outcome: RetryProbeOutcome?) -> String {
      switch outcome {
      case .remaining(let count):
        if count.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed {
          String(localized: "\(count.attemptsRemaining) attempts remaining")
        } else {
          String(localized: "\(count.attemptsRemaining) attempts remaining - low")
        }
      case .verified:
        String(localized: "verified this session")
      case .locked:
        String(localized: "blocked - unblock with the PUK")
      case .invalidated:
        String(localized: "invalidated - contact the issuer")
      case .noInformation, .other:
        String(localized: "state unknown")
      case .none:
        String(localized: "no card present")
      }
    }

    /// One probe outcome as a short cell.
    private static func attemptsText(_ outcome: RetryProbeOutcome?) -> String {
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

    /// Green is room, orange is the floor coming, red is the edge.
    private static func attemptsColor(_ outcome: RetryProbeOutcome?) -> Color {
      switch outcome {
      case .remaining(let count):
        count.isBlocked
          ? .red
          : count.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed
            ? .green
            : .orange
      case .verified:
        .green
      case .locked, .invalidated:
        .red
      case .noInformation, .other, .none:
        .secondary
      }
    }

    /// One credential's reading: a symbol and text carry the state, the
    /// color only underlines it - never color alone.
    @ViewBuilder
    private func attemptsRow(_ name: String, _ outcome: RetryProbeOutcome?) -> some View {
      LabeledContent(name) {
        HStack(spacing: Self.rowSymbolSpacing) {
          Image(systemName: Self.attemptsSymbol(outcome))
          Text(Self.attemptsText(outcome))
            .monospacedDigit()
        }
        .foregroundStyle(Self.attemptsColor(outcome))
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(name)
      .accessibilityValue(Self.attemptsSpoken(outcome))
    }

    /// Speaks an outcome the moment it lands, for a VoiceOver user
    /// whose focus is not on the outcome row.
    private func announce(_ message: String?) {
      guard let message else { return }
      AccessibilityNotification.Announcement(message).post()
    }

    /// Opens on what the card needs, until the holder chooses.
    private func suggestTask(from report: CredentialProbeReport?) {
      guard !hasChosenTask, let report else { return }
      let blocked: [RetryProbeOutcome] = [.locked, .invalidated]
      if blocked.contains(report.pin1) || blocked.contains(report.pin2) {
        task = .unblock
      }
    }
  }

#endif
