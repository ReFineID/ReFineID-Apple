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
      case unblockPin1
      case unblockPin2
      case activate

      internal var id: Self { self }

      /// The tab's label, which names the credential it spends.
      ///
      /// Two tasks that differ only in which PIN they touch must not
      /// share a label, and neither may hide that choice one level
      /// down: a holder who means PIN 2 must not be able to change
      /// PIN 1 by missing a control inside the page.
      internal var name: String {
        switch self {
        case .changePin1:
          String(localized: "Change PIN 1")
        case .changePin2:
          String(localized: "Change PIN 2")
        case .unblockPin1:
          String(localized: "Unblock PIN 1")
        case .unblockPin2:
          String(localized: "Unblock PIN 2")
        case .activate:
          String(localized: "Activate")
        }
      }
    }

    /// Window identity, for the menu command that opens it.
    internal static let windowID = "pin-management"

    private static let windowWidth: CGFloat = 460

    /// Internal, not private: the counter presentation lives in
    /// CardManagementView+Attempts.swift and lays out the same row.
    internal static let rowSymbolSpacing: CGFloat = 4

    private static let attemptsSpacing: CGFloat = 14

    private static let barHorizontalPadding: CGFloat = 16

    private static let barVerticalPadding: CGFloat = 6

    private static let barLineSpacing: CGFloat = 4

    @State private var model = CardManagementModel()
    @State private var task: ManagementTask = .changePin1
    @State private var hasChosenTask = false

    internal var body: some View {
      Form {
        taskSection
        outcomeSection
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.windowWidth)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        attemptsBar
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

    /// The counters, pinned along the foot of the window.
    ///
    /// A status bar rather than a section: these are what the window
    /// is judged against, not what it is for, so they stay pinned
    /// along the foot without taking a place in the form. They are
    /// still the numbers that decide whether the task can run, so the
    /// bar says so in words when one of them refuses.
    @ViewBuilder private var attemptsBar: some View {
      VStack(alignment: .leading, spacing: Self.barLineSpacing) {
        HStack(spacing: Self.attemptsSpacing) {
          Text("Attempts left:")
            .foregroundStyle(.secondary)
          attemptsEntry("PIN 1", model.report?.pin1)
          attemptsEntry("PIN 2", model.report?.pin2)
          attemptsEntry("PUK", model.report?.puk)
          Spacer()
        }
        if refusesAnyCredential {
          Text(
            "ReFineID will not use a credential with one or two "
              + "attempts left. Restore it with other software, or "
              + "unblock it here once the card has blocked it."
          )
          .foregroundStyle(.red)
        }
      }
      .font(.footnote)
      .padding(.horizontal, Self.barHorizontalPadding)
      .padding(.vertical, Self.barVerticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
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
      case .unblockPin1:
        CredentialUnblockSection(model: model, target: .pin1)
      case .unblockPin2:
        CredentialUnblockSection(model: model, target: .pin2)
      case .activate:
        CardActivationSection(model: model)
      }
    }

    /// The one place outcomes are shown.
    @ViewBuilder private var outcomeSection: some View {
      if model.working || model.failure != nil || model.notice != nil {
        Section {
          if model.working {
            Text("Talking to the card…")
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
      // Land on the page for the credential that is actually blocked,
      // so the form in front of the holder spends the one they came
      // for. PIN 1 first when both are: it is the one a card needs to
      // be usable at all.
      if blocked.contains(report.pin1) {
        task = .unblockPin1
      } else if blocked.contains(report.pin2) {
        task = .unblockPin2
      }
    }
  }

#endif
