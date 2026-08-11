//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
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
    internal enum ManagementTask: CaseIterable, Identifiable {
      case changePin1
      case changePin2
      case resetPin1
      case resetPin2

      internal var id: Self { self }

      /// The tab's label, naming the action and the credential.
      internal var name: String {
        switch self {
        case .changePin1:
          String(localized: "Change PIN 1")
        case .changePin2:
          String(localized: "Change PIN 2")
        case .resetPin1:
          String(localized: "Reset PIN 1")
        case .resetPin2:
          String(localized: "Reset PIN 2")
        }
      }
    }

    /// Window identity, for the menu command that opens it.
    internal static let windowID = "pin-management"

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

    @State private var model = CardManagementModel()
    @State private var task: ManagementTask = .changePin1
    @State private var hasChosenTask = false

    internal var body: some View {
      taskSection
        .frame(minWidth: windowWidth)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          attemptsBar
        }
        .task { await model.refresh() }
        .onChange(of: model.report) { _, report in
          suggestTask(from: report)
        }
        .announcesOutcome(model.failure)
        .announcesOutcome(model.notice)
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
    /// Whether this card is still waiting to be taken into use.
    ///
    /// Activation sets both PINs from the code in the issuance letter,
    /// so while it is available there is nothing else to offer: a PIN
    /// that has never been set cannot be changed, and resetting one
    /// would be a second door to the same operation with a retry spent
    /// on getting there.
    private var awaitsActivation: Bool {
      model.offersActivation
    }

    /// One tab per task, and only the chosen one on screen.
    ///
    /// Tabs rather than a list: every task the card allows is named in
    /// full and visible at once, so the credential is chosen with the
    /// action in a single act.
    @ViewBuilder private var taskSection: some View {
      if awaitsActivation {
        Form {
          CardActivationSection(model: model)
          outcomeSection
        }
        .formStyle(.grouped)
      } else {
        TabView(selection: $task) {
          ForEach(ManagementTask.allCases) { candidate in
            Form {
              page(for: candidate)
              outcomeSection
            }
            .formStyle(.grouped)
            .tabItem { Text(candidate.name) }
            .tag(candidate)
          }
        }
        .disabled(model.working)
        .accessibilityIdentifier("managementTask")
        .onChange(of: task) { _, _ in
          hasChosenTask = true
        }
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
      guard !hasChosenTask, !awaitsActivation, let report else { return }
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

#endif
