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
    internal static let windowID = "pin-management"

    private static let windowWidth: CGFloat = 460

    private static let rowSymbolSpacing: CGFloat = 4

    private static let attemptsSpacing: CGFloat = 14

    @State private var model = CardManagementModel()
    @State private var task: ManagementTask = .changePin1
    @State private var hasChosenTask = false

    internal var body: some View {
      Form {
        taskSection
        outcomeSection
        attemptsSection
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

    /// The counter-safe reading, as one quiet line.
    ///
    /// Attempts remaining are worth knowing and are not why the window
    /// was opened, so they sit under the task rather than above it.
    @ViewBuilder private var attemptsSection: some View {
      Section {
        HStack(spacing: Self.attemptsSpacing) {
          attemptsEntry("PIN1", model.report?.pin1)
          attemptsEntry("PIN2", model.report?.pin2)
          attemptsEntry("PUK", model.report?.puk)
          Spacer()
        }
        .font(.footnote)
      } header: {
        Text("Attempts remaining")
      }
    }

    /// The tasks this card can actually be asked to do.
    ///
    /// Activation is offered only while the card is still in its
    /// factory state; for a card in use there is no such operation,
    /// and showing it would invite a retry spent for nothing.
    private var offeredTasks: [ManagementTask] {
      ManagementTask.allCases.filter { candidate in
        candidate != .activate || model.offersActivation
      }
    }

    /// The chosen task, and only it.
    @ViewBuilder private var taskSection: some View {
      Section {
        Picker("Task", selection: $task) {
          ForEach(offeredTasks) { candidate in
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

    /// The colour-independent marker for a count that needs one, or
    /// nil while the credential is healthy.
    private static func attemptsWarning(_ outcome: RetryProbeOutcome?) -> String? {
      switch outcome {
      case .remaining(let count):
        if count.isBlocked {
          "xmark.octagon.fill"
        } else if count.attemptsRemaining < RetryFloor.minimumAttemptsToProceed {
          "exclamationmark.triangle.fill"
        } else {
          nil
        }
      case .verified:
        nil
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
        if count.isBlocked {
          .red
        } else if count.attemptsRemaining < RetryFloor.minimumAttemptsToProceed {
          .orange
        } else {
          .secondary
        }
      case .verified:
        .secondary
      case .locked, .invalidated:
        .red
      case .noInformation, .other, .none:
        .secondary
      }
    }

    /// One credential's reading.
    ///
    /// A symbol appears only when the count is not healthy, so the
    /// line stays quiet while everything is fine and still never
    /// relies on colour alone when it is not.
    @ViewBuilder
    private func attemptsEntry(
      _ name: String,
      _ outcome: RetryProbeOutcome?
    ) -> some View {
      HStack(spacing: Self.rowSymbolSpacing) {
        if let symbol = Self.attemptsWarning(outcome) {
          Image(systemName: symbol)
        }
        Text("\(name) \(Self.attemptsText(outcome))")
          .monospacedDigit()
      }
      .foregroundStyle(Self.attemptsColor(outcome))
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
      // A task that stopped being offered cannot stay selected.
      if !offeredTasks.contains(task) {
        task = .changePin1
      }
      guard !hasChosenTask else { return }
      if model.offersActivation {
        task = .activate
        return
      }
      guard let report else { return }
      let blocked: [RetryProbeOutcome] = [.locked, .invalidated]
      if blocked.contains(report.pin1) || blocked.contains(report.pin2) {
        task = .unblock
      }
    }
  }

#endif
