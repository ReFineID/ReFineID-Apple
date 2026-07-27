import CardCore
import SwiftUI

/// The diagnostics screen: what the extensions did, and the state they did
/// it in.
///
/// One tap from the status screen, and deliberately plain. It is read on a
/// phone that has just failed to log in, usually by someone standing over
/// a card reader, and every line on it exists because its absence once
/// made a failure unreadable. The text is monospaced and selectable, and
/// there is a share and a copy action, because the trace is only useful
/// once it is off the device.
///
/// Clearing is here for the same reason the reset mode is: every
/// measurement starts from zero, or a line from the previous attempt reads
/// as if this attempt had made it.
internal struct DiagnosticsView: View {
  /// Space between two sections.
  private static let sectionSpacing: CGFloat = 20

  /// Space between a section title and its lines.
  private static let lineSpacing: CGFloat = 4

  /// Padding around the whole capture.
  private static let contentPadding: CGFloat = 16

  /// The capture on screen, or nil until the first read finishes.
  @State private var snapshot: DiagnosticsSnapshot?

  /// Why a clear did not clear, when it did not.
  @State private var clearNote: String?

  internal var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Self.sectionSpacing) {
        if let clearNote {
          Text(clearNote)
            .foregroundStyle(.red)
        }
        if let snapshot {
          ForEach(snapshot.sections) { section in
            sectionView(section)
          }
        } else {
          Text("Reading...")
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Self.contentPadding)
    }
    .navigationTitle("Diagnostics")
    .toolbar { toolbarContent }
    .task { snapshot = DiagnosticsSnapshot.collect() }
  }

  /// Refresh, share, copy and clear.
  ///
  /// Share and copy both appear: a share sheet sends the capture to
  /// someone else, the pasteboard puts it where the person holding the
  /// phone is already working.
  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItem {
      Button("Refresh") {
        snapshot = DiagnosticsSnapshot.collect()
      }
    }
    ToolbarItem {
      ShareLink(item: snapshot?.text ?? "")
    }
    ToolbarItem {
      Button("Copy") {
        DiagnosticsClipboard.copy(snapshot?.text ?? "")
      }
    }
    ToolbarItem {
      Button("Clear", role: .destructive) {
        let status = ExtensionTrace.clear()
        snapshot = DiagnosticsSnapshot.collect()
        clearNote =
          status == errSecSuccess || status == errSecItemNotFound
          ? nil : String(localized: "Clear refused by the keychain: \(Int(status))")
      }
    }
  }

  /// One titled block, its lines monospaced so columns line up between
  /// two captures.
  @ViewBuilder
  private func sectionView(_ section: DiagnosticsSnapshot.Section) -> some View {
    VStack(alignment: .leading, spacing: Self.lineSpacing) {
      Text(verbatim: section.title)
        .font(.headline)
      Text(verbatim: section.lines.joined(separator: "\n"))
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }
  }
}

#Preview {
  DiagnosticsView()
}
