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

      /// The tab's label: short, because a segmented control shows
      /// every option at once and the fields beneath say the rest.
      internal var name: String {
        switch self {
        case .changePin1:
          String(localized: "PIN1")
        case .changePin2:
          String(localized: "PIN2")
        case .unblock:
          String(localized: "Unblock")
        case .activate:
          String(localized: "Activate")
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

    /// The counters, at the foot of the window.
    ///
    /// Reference information rather than the reason the window was
    /// opened, so it sits under the task - but it is the number that
    /// decides whether the task can run at all, so it is legible at a
    /// glance and says so when it refuses.
    @ViewBuilder private var attemptsSection: some View {
      Section {
        HStack(spacing: Self.attemptsSpacing) {
          attemptsEntry("PIN1", model.report?.pin1)
          attemptsEntry("PIN2", model.report?.pin2)
          attemptsEntry("PUK", model.report?.puk)
          Spacer()
        }
        .font(.footnote)
        if refusesAnyCredential {
          Text(
            "ReFineID will not use a credential with one or two "
              + "attempts left. Restore it to five with other software, "
              + "or unblock it here once the card has blocked it."
          )
          .font(.footnote)
          .foregroundStyle(.red)
        }
      } header: {
        Text("Attempts left")
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
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(model.working)
        .accessibilityIdentifier("managementTask")
        .accessibilityLabel("Task")
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

    /// Whether any credential sits in the band this app will not use.
    private var refusesAnyCredential: Bool {
      guard let report = model.report else { return false }
      return [report.pin1, report.pin2, report.puk].contains { outcome in
        guard case .remaining(let count) = outcome else { return false }
        return !count.isBlocked
          && count.attemptsRemaining < RetryFloor.minimumAttemptsToProceed
      }
    }

    /// The marker beside each count, so the band is never carried by
    /// colour alone.
    private static func attemptsSymbol(_ outcome: RetryProbeOutcome?) -> String {
      switch outcome {
      case .remaining(let count):
        if count.isBlocked {
          "arrow.counterclockwise.circle.fill"
        } else if count.attemptsRemaining < RetryFloor.minimumAttemptsToProceed {
          "xmark.octagon.fill"
        } else if count.attemptsRemaining < RetryCount.pristineAllowance {
          "exclamationmark.triangle.fill"
        } else {
          "checkmark.circle.fill"
        }
      case .verified:
        "checkmark.circle.fill"
      case .locked:
        "arrow.counterclockwise.circle.fill"
      case .invalidated:
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

    /// One probe outcome as a short cell, counted against a full card.
    private static func attemptsText(_ outcome: RetryProbeOutcome?) -> String {
      switch outcome {
      case .remaining(let count):
        "\(count.attemptsRemaining)/\(RetryCount.pristineAllowance)"
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

    /// Full is green, short of full is orange, refused is red, and
    /// blocked is blue - blocked being the one state that is not a
    /// warning but an instruction: the PUK undoes it.
    private static func attemptsColor(_ outcome: RetryProbeOutcome?) -> Color {
      switch outcome {
      case .remaining(let count):
        if count.isBlocked {
          .blue
        } else if count.attemptsRemaining < RetryFloor.minimumAttemptsToProceed {
          .red
        } else if count.attemptsRemaining < RetryCount.pristineAllowance {
          .orange
        } else {
          .green
        }
      case .verified:
        .green
      case .locked:
        .blue
      case .invalidated:
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
        Text("\(name) \(Self.attemptsText(outcome))")
          .monospacedDigit()
        Image(systemName: Self.attemptsSymbol(outcome))
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
