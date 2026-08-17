// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

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
  private struct ReaderReadKey: Equatable {
    let isPresent: Bool
    let isReady: Bool
    let transport: CardMaintenance.Transport
  }

  /// The four things this window does to a credential in use.
  ///
  /// Each is one tab, named in full. The action and the credential
  /// are read together or not at all: a holder who means PIN 2 must
  /// not reach PIN 1, and must not have to make two choices to say
  /// one thing.
  ///
  /// Reset rather than unblock: the card resets the retry counter and
  /// takes a new value whether or not the credential was blocked, so
  /// someone who has forgotten a PIN does not have to exhaust it
  /// first to be allowed a new one.
  internal enum ManagementTask: CaseIterable, Identifiable, Equatable {
    case changePin1
    case changePin2
    case resetPin1
    case resetPin2

    internal var id: Self { self }

    /// The tab's label, naming the action and the credential.
    internal var name: String {
      switch self {
      case .changePin1:
        String(localized: "Change Basic PIN 1")
      case .changePin2:
        String(localized: "Change Signature PIN 2")
      case .resetPin1:
        String(localized: "Reset Basic PIN 1")
      case .resetPin2:
        String(localized: "Reset Signature PIN 2")
      }
    }
  }

  #if os(macOS)
    /// Internal, not private: the counter presentation lives in
    /// CardManagementView+Attempts.swift and lays out the same row.
    internal static let rowSymbolSpacing: CGFloat = 4

    private static let attemptsSpacing: CGFloat = 14

    private static let barHorizontalPadding: CGFloat = 16

    private static let barVerticalPadding: CGFloat = 6

    private static let barLineSpacing: CGFloat = 4

    /// The window's own width, which grows with the text inside it.
    @ScaledMetric(relativeTo: .body)
    private var windowWidth: CGFloat = 560
  #endif

  private let startsWithReaderCard: Bool
  private let usesProvidedCardAccessNumber: Bool
  private let activationRequired: Bool
  private let onActivationSucceeded: () -> Void
  private let cardPresence = CardPresence.shared
  private let retryHealth = CredentialRetryHealth.shared
  @Environment(\.dismiss) private var dismiss

  @State private var model: CardManagementModel
  @State private var task: ManagementTask
  @State private var hasChosenTask = false

  internal init(
    readerCardIsPresent: Bool = false,
    activationRequired: Bool = false,
    cardAccessNumber: String? = nil,
    activationScheme: ActivationScheme? = nil,
    activationNeeds: CardActivationNeeds? = nil,
    onActivationSucceeded: @escaping () -> Void = {}
  ) {
    startsWithReaderCard = readerCardIsPresent
    self.activationRequired = activationRequired
    usesProvidedCardAccessNumber =
      cardAccessNumber?.count == CardAccessNumber.digitCount
    self.onActivationSucceeded = onActivationSucceeded
    _model = State(
      initialValue: CardManagementModel(
        transport: readerCardIsPresent
          ? .reader
          : (usesProvidedCardAccessNumber ? .nearField : nil),
        activationRequired: activationRequired,
        cardAccessNumber: cardAccessNumber,
        activationScheme: activationScheme,
        activationNeeds: activationNeeds
      )
    )
    _task = State(
      initialValue: Self.initialTask(
        for: CredentialRetryHealth.shared.recovery)
    )
  }

  private var readerCardIsPresent: Bool {
    #if os(iOS)
      if DemoMode.shared.isActive {
        return DemoMode.shared.isReaderCardPresent
      }
    #endif
    return cardPresence.hasCompletedInitialScan
      ? cardPresence.isReaderCardPresent
      : startsWithReaderCard
  }

  private var readerCardIsReady: Bool {
    #if os(iOS)
      if DemoMode.shared.isActive {
        return DemoMode.shared.isReaderCardPresent
      }
    #endif
    return cardPresence.hasCompletedInitialScan && cardPresence.isReaderCardReady
  }

  private var readerReadKey: ReaderReadKey {
    ReaderReadKey(
      isPresent: readerCardIsPresent,
      isReady: readerCardIsReady,
      transport: model.transport
    )
  }

  internal var body: some View {
    taskSection
      #if os(macOS)
        .frame(minWidth: windowWidth)
      #else
        .navigationTitle(
          awaitsActivation ? "ReFineID" : "Personal Identification Numbers"
        )
        .navigationBarTitleDisplayMode(awaitsActivation ? .large : .inline)
      #endif
      #if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if !awaitsActivation, model.report != nil {
            attemptsBar
          }
        }
      #endif
      #if os(macOS)
        .task { await model.refresh() }
      #endif
      #if os(iOS)
        .task(id: readerReadKey) {
          if readerCardIsPresent {
            model.transport = .reader
            guard readerCardIsReady else { return }
            // The token insertion event has already classified this as
            // an unactivated card. Do not hold the activation form behind
            // a second full credential probe; activation performs its own
            // retry-floor checks inside the exclusive card session.
            if awaitsActivation {
              await model.detectActivationScheme()
            } else {
              await model.refresh()
            }
          } else if model.transport == .reader {
            model.cardRemoved()
            dismiss()
          }
        }
      #endif
      .onChange(of: model.report) { _, report in
        suggestTask(from: report)
      }
      #if os(macOS)
        .announcesOutcome(model.failure)
        .announcesOutcome(model.notice)
      #endif
  }

  /// The counters, pinned along the foot of the window.
  ///
  /// A status bar rather than a section: these are what the window
  /// is judged against, not what it is for, so they stay pinned
  /// along the foot without taking a place in the form. They are
  /// still the numbers that decide whether the task can run, so the
  /// bar says so in words when one of them refuses.
  #if os(macOS)
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
      }
      .font(.footnote)
      .padding(.horizontal, Self.barHorizontalPadding)
      .padding(.vertical, Self.barVerticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
    }
  #endif

  /// The tasks this card can actually be asked to do.
  ///
  /// Activation is offered only while the card is still in its
  /// factory state; for a card in use there is no such operation,
  /// and showing it would invite a retry spent for nothing.
  /// Whether this card is still waiting to be taken into use.
  ///
  /// Activation sets both PINs from the code in the issuance letter,
  /// so while it is available there is nothing else to offer: a PIN
  /// that has never been set cannot be changed, and resetting one
  /// would be a second door to the same operation with a retry spent
  /// on getting there.
  private var awaitsActivation: Bool {
    activationRequired || model.offersActivation
  }

  /// One segment per task, and only the chosen one on screen.
  ///
  /// A segmented control rather than tabs: this view is a pane of
  /// the settings window, whose tab bar is the window's own - a
  /// nested TabView's items are hoisted up beside the panes, four
  /// tasks impersonating four settings panes. The segments keep
  /// what the tabs gave: every task the card allows named in full
  /// and visible at once, so the credential is chosen with the
  /// action in a single act.
  @ViewBuilder private var taskSection: some View {
    if awaitsActivation {
      Form {
        connectionSection
        CardActivationSection(
          model: model,
          onActivated: activationCompleted)
        CardOutcomeSection(model: model)
      }
      .formStyle(.grouped)
    } else {
      Form {
        connectionSection
        let tasks = availableTasks
        if !tasks.isEmpty {
          Picker("Task", selection: $task) {
            ForEach(tasks) { candidate in
              Text(candidate.name).tag(candidate)
            }
          }
          // Every task name gets a full-width line of its own: the
          // floating menu and the segmented bar both truncated the
          // longer localizations.
          #if os(iOS)
            .pickerStyle(.inline)
          #else
            .pickerStyle(.radioGroup)
          #endif
          .labelsHidden()
          .accessibilityIdentifier("managementTask")
          if model.notice == nil, tasks.contains(task) {
            page(for: task)
          }
        }
        CardOutcomeSection(model: model)
        recoveryGuidanceSection
      }
      .formStyle(.grouped)
      .disabled(model.working)
      .onChange(of: task) { _, _ in
        hasChosenTask = true
        model.clearOutcome()
      }
    }
  }

  /// A critical card is a recovery workflow, never a PIN-change workflow.
  private var availableTasks: [ManagementTask] {
    switch retryHealth.recovery {
    case .resetPin1, .resetPin2:
      [.resetPin1, .resetPin2]
    case .useOtherSoftware, .unrecoverable:
      []
    case nil:
      ManagementTask.allCases
    }
  }

  private static func initialTask(
    for recovery: CredentialRetryHealth.Recovery?
  ) -> ManagementTask {
    switch recovery {
    case .resetPin1:
      .resetPin1
    case .resetPin2:
      .resetPin2
    case .useOtherSoftware, .unrecoverable, nil:
      .changePin1
    }
  }

  @ViewBuilder private var recoveryGuidanceSection: some View {
    if model.failure == nil, model.notice == nil {
      switch retryHealth.recovery {
      case .resetPin1:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.recoveryGuidance(for: .pin1),
            tone: .notice)
        }
      case .resetPin2:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.recoveryGuidance(for: .pin2),
            tone: .notice)
        }
      case .useOtherSoftware:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.otherSoftwareRecovery(),
            tone: .failure)
        }
      case .unrecoverable:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.unrecoverableCard(),
            tone: .failure)
        }
      case nil:
        spentAttemptsSection
      }
    }
  }

  /// The yellow key's explanation: which codes have spent attempts,
  /// how many remain, and that one correct entry restores them all.
  @ViewBuilder private var spentAttemptsSection: some View {
    if retryHealth.level == .warning, let report = retryHealth.report {
      let spent = Self.spentAttempts(report)
      if !spent.isEmpty {
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.spentAttemptsNotice(spent),
            tone: .notice)
        }
      }
    }
  }

  private static func spentAttempts(
    _ report: CredentialProbeReport
  ) -> [(name: String, remaining: RetryCount)] {
    [("PIN 1", report.pin1), ("PIN 2", report.pin2), ("PUK", report.puk)]
      .compactMap { name, outcome in
        guard case .remaining(let count) = outcome, !count.isPristine
        else { return nil }
        return (name, count)
      }
  }

  private func activationCompleted() {
    onActivationSucceeded()
    dismiss()
  }

  @ViewBuilder private var connectionSection: some View {
    #if os(iOS)
      if !readerCardIsPresent,
        model.transport == .nearField,
        !usesProvidedCardAccessNumber
      {
        Section("NFC") {
          TextField("Card Access Number (CAN)", text: $model.cardAccessNumber)
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: model.cardAccessNumber) { _, typed in
              model.cardAccessNumber = LimitedDigits.cardAccessNumber(typed)
            }
            .accessibilityIdentifier("managementCardAccessNumber")
          Button("Read card") {
            Task { await model.refresh() }
          }
          .disabled(model.cardOperationInProgress || !model.canContactCard)
          .accessibilityIdentifier("managementReadCard")
        }
      }
    #endif
  }

  /// The form one tab shows.
  @ViewBuilder
  private func page(for task: ManagementTask) -> some View {
    switch task {
    case .changePin1:
      CredentialChangeSection(model: model, credential: .pin1)
    case .changePin2:
      CredentialChangeSection(model: model, credential: .pin2)
    case .resetPin1:
      CredentialUnblockSection(model: model, target: .pin1)
    case .resetPin2:
      CredentialUnblockSection(model: model, target: .pin2)
    }
  }

  /// Opens on what the card needs, until the holder chooses.
  private func suggestTask(from report: CredentialProbeReport?) {
    guard !awaitsActivation, let report else { return }
    let recoveryTask: ManagementTask? =
      switch retryHealth.recovery {
      case .resetPin1:
        .resetPin1
      case .resetPin2:
        .resetPin2
      case .useOtherSoftware, .unrecoverable, nil:
        nil
      }
    if let recoveryTask {
      if !availableTasks.contains(task)
        || (!hasChosenTask && model.notice == nil)
      {
        task = recoveryTask
      }
      return
    }
    guard !hasChosenTask else { return }
    let blocked: [RetryProbeOutcome] = [.locked, .invalidated]
    // Land on the credential that is actually blocked, so the form in
    // front of the holder spends the one they came for. PIN 1 first
    // when both are: it is the one a card needs to be usable at all.
    if blocked.contains(report.pin1) {
      task = .resetPin1
    } else if blocked.contains(report.pin2) {
      task = .resetPin2
    }
  }
}
