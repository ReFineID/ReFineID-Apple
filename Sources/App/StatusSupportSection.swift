import SwiftUI

/// Support and recovery stay visible without crowding the technical report.
internal struct StatusSupportSection: View {
  @Binding internal var showsDiagnostics: Bool

  internal var body: some View {
    Section {
      diagnosticsLink
    } header: {
      Text("Support")
    }
  }

  @ViewBuilder private var diagnosticsLink: some View {
    #if os(iOS)
      NavigationLink {
        DiagnosticsView()
      } label: {
        Label("Diagnostics", systemImage: "stethoscope")
      }
      .accessibilityIdentifier("diagnosticsButton")
    #else
      Button("Diagnostics") {
        showsDiagnostics = true
      }
      .accessibilityIdentifier("diagnosticsButton")
    #endif
  }
}
