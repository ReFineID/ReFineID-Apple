import CardCore
import SwiftUI

/// A read-only technical report for support and development.
///
/// A native list owns scrolling, safe areas, and Dynamic Type. Report
/// actions live in the navigation toolbar; card removal belongs on setup.
internal struct DiagnosticsView: View {
  // Two seconds is long enough to notice without leaving stale feedback.
  // swiftlint:disable:next no_magic_numbers
  private static let copyFeedbackDuration: Duration = .seconds(2)

  @State private var snapshot: DiagnosticsSnapshot?
  @State private var reportCopied = false
  @State private var clearMessage: String?
  @State private var clearSucceeded = true
  @State private var showsClearConfirmation = false

  internal var body: some View {
    List {
      if let clearMessage {
        Section {
          Label(
            clearMessage,
            systemImage: clearSucceeded
              ? "checkmark.circle" : "exclamationmark.triangle"
          )
          .foregroundStyle(clearSucceeded ? Color.secondary : Color.red)
        }
      }
      if let snapshot {
        ForEach(snapshot.sections) { section in
          reportSection(section)
        }
      } else {
        Section {
          HStack {
            ProgressView()
            Text("Reading report")
          }
        }
      }
      clearLogsSection
    }
    .navigationTitle("Diagnostics")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar { toolbarContent }
    .task { refresh() }
    .confirmationDialog(
      "Clear diagnostic logs?",
      isPresented: $showsClearConfirmation,
      titleVisibility: .visible
    ) {
      Button("Clear diagnostic logs", role: .destructive) {
        clearLogs()
      }
      Button("Cancel", role: .cancel) {
        // The system dismisses the confirmation dialog.
      }
    } message: {
      Text(
        """
        This clears ReFineID's diagnostic trace. It does not remove your \
        card details or Safari identity.
        """)
    }
  }

  /// Refresh, share, and copy use standard navigation-bar actions.
  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button {
        refresh()
      } label: {
        Label("Refresh report", systemImage: "arrow.clockwise")
      }
    }
    ToolbarItem(placement: .primaryAction) {
      ShareLink(item: snapshot?.text ?? "") {
        Label("Share report", systemImage: "square.and.arrow.up")
      }
      .disabled(snapshot == nil)
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        copyReport()
      } label: {
        Label(
          reportCopied ? "Report copied" : "Copy report",
          systemImage: reportCopied ? "checkmark" : "doc.on.doc"
        )
      }
      .disabled(snapshot == nil)
    }
  }

  /// Trace removal is separate from report reading and requires
  /// confirmation because it removes evidence from the previous attempt.
  private var clearLogsSection: some View {
    Section {
      Button("Clear diagnostic logs", role: .destructive) {
        showsClearConfirmation = true
      }
    } footer: {
      Text("Clears only ReFineID's diagnostic trace.")
    }
  }

  /// One selectable, monospaced report block.
  private func reportSection(_ section: DiagnosticsSnapshot.Section) -> some View {
    Section {
      Text(verbatim: section.lines.joined(separator: "\n"))
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    } header: {
      Text(verbatim: section.title)
    }
  }

  private func refresh() {
    snapshot = DiagnosticsSnapshot.collect()
  }

  private func copyReport() {
    guard let snapshot else { return }
    DiagnosticsClipboard.copy(snapshot.text)
    reportCopied = true
    Task {
      try? await Task.sleep(for: Self.copyFeedbackDuration)
      reportCopied = false
    }
  }

  private func clearLogs() {
    let status = ExtensionTrace.clear()
    clearSucceeded = status == errSecSuccess || status == errSecItemNotFound
    clearMessage =
      clearSucceeded
      ? String(localized: "Diagnostic logs cleared.")
      : String(localized: "The keychain refused to clear the logs (\(Int(status))).")
    refresh()
  }
}

#Preview {
  NavigationStack {
    DiagnosticsView()
  }
}
