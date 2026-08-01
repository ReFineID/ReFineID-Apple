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
    // An alert, not a confirmation dialog: a dialog is presented as a
    // popover anchored to its source, which drops the cancel action and
    // was measured landing over the navigation bar, far from the button
    // that opened it. An alert is centered and always keeps both.
    .alert(
      "Clear diagnostic logs?",
      isPresented: $showsClearConfirmation
    ) {
      Button("Clear", role: .destructive) {
        clearLogs()
      }
      Button("Cancel", role: .cancel) {
        // The system dismisses the alert.
      }
    } message: {
      Text(
        """
        This clears ReFineID's diagnostic trace. It does not remove your \
        card details or Safari identity.
        """)
    }
  }

  /// Refresh stays a button; the two report exports share one menu, so
  /// the bar keeps two controls instead of three and the title fits.
  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button {
        refresh()
      } label: {
        Label("Refresh report", systemImage: "arrow.clockwise")
      }
    }
    ToolbarItem(placement: .primaryAction) {
      Menu {
        Button {
          copyReport()
        } label: {
          Label("Copy report", systemImage: "doc.on.doc")
        }
        ShareLink(item: snapshot?.text ?? "") {
          Label("Share report", systemImage: "square.and.arrow.up")
        }
      } label: {
        Label(
          reportCopied ? "Report copied" : "Report actions",
          systemImage: reportCopied ? "checkmark" : "square.and.arrow.up")
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
  ///
  /// The block scrolls sideways rather than wrapping: these are fixed
  /// columns of status words and identifiers, and a wrapped line reads
  /// as two records instead of one.
  private func reportSection(_ section: DiagnosticsSnapshot.Section) -> some View {
    Section {
      ScrollView(.horizontal) {
        Text(verbatim: section.lines.joined(separator: "\n"))
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
      .scrollIndicators(.hidden)
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
