import CardCore
import SwiftUI

/// Card, reader, and Safari identity status.
///
/// On iOS the form is the page's scrolling root. This lets navigation,
/// Dynamic Type, VoiceOver, safe areas, and compact screens behave like
/// other system forms instead of imposing a desktop-sized custom layout.
internal struct StatusView: View {
  private static let hexRadix = 16

  #if os(macOS)
    private static let desktopSpacing: CGFloat = 12
    private static let desktopPadding: CGFloat = 24
    private static let desktopMinimumWidth: CGFloat = 560
  #endif

  @State private var model = CardStatusModel()
  @State private var credentials = CardCredentialsModel()

  #if DEBUG
    @State private var showsDiagnostics = false
  #endif

  /// Whether Safari cannot currently offer a readable card's identity.
  ///
  /// Reseating is the one useful recovery action here.
  private var needsReseating: Bool {
    guard let snapshot = model.snapshot, !snapshot.safariIdentityPresent else {
      return false
    }
    switch snapshot.card {
    case .sealed:
      return credentials.contents.hasCardAccessNumber
    case .supported:
      return true
    case .failed, .noCard, .unsupported:
      return false
    }
  }

  internal var body: some View {
    #if os(iOS)
      phoneBody
    #else
      desktopBody
    #endif
  }

  #if os(iOS)
    /// A native phone hierarchy: one scrolling form, a navigation title,
    /// and secondary tools reached through disclosure rows.
    private var phoneBody: some View {
      Form {
        statusSections
        #if DEBUG
          supportSection
        #endif
      }
      .navigationTitle("Card status")
      .navigationBarTitleDisplayMode(.inline)
      .refreshable { await model.refresh() }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await model.refresh() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .disabled(model.isRefreshing)
        }
      }
      .task { await load() }
    }
  #else
    /// The macOS status window remains a fixed-width utility window.
    private var desktopBody: some View {
      VStack(alignment: .leading, spacing: Self.desktopSpacing) {
        Text(verbatim: "ReFineID")
          .font(.largeTitle.bold())
        Text("Finnish identity card middleware")
          .foregroundStyle(.secondary)
        Form {
          statusSections
          #if DEBUG
            supportSection
          #endif
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        Button("Refresh") {
          Task { await model.refresh() }
        }
        .disabled(model.isRefreshing)
      }
      .padding(Self.desktopPadding)
      .frame(minWidth: Self.desktopMinimumWidth, alignment: .leading)
      .task { await load() }
      #if DEBUG
        .sheet(isPresented: $showsDiagnostics) {
          NavigationStack {
            DiagnosticsView()
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Done") { showsDiagnostics = false }
              }
            }
          }
        }
      #endif
    }
  #endif

  #if DEBUG
    private var supportSection: some View {
      StatusSupportSection(
        showsDiagnostics: $showsDiagnostics
      )
    }
  #endif

  /// Read-only state.
  ///
  /// Recovery is kept separate in the Support section.
  @ViewBuilder private var statusSections: some View {
    Section("Card") {
      LabeledContent("Reader", value: readerLabel)
      cardRows
      cardTypeRow
    }
    Section("Safari") {
      LabeledContent("Login identity", value: Self.safariLabel(for: model.snapshot))
      if needsReseating {
        Label(
          "Remove the card and put it back so the system reads it again.",
          systemImage: "arrow.counterclockwise"
        )
      }
    }
  }

  private var readerLabel: String {
    guard let snapshot = model.snapshot else {
      return String(localized: "Checking...")
    }
    return snapshot.readerName ?? String(localized: "No reader connected")
  }

  /// The card type when its answer to reset identifies it.
  @ViewBuilder private var cardTypeRow: some View {
    if let identified = model.snapshot?.cardType {
      switch identified.confidence {
      case .documented:
        LabeledContent("Card type", value: identified.name)
      case .generationOnly:
        LabeledContent(
          "Card type",
          value: String(localized: "\(identified.name), variant not in DVV's table")
        )
      }
    }
  }

  @ViewBuilder private var cardRows: some View {
    switch model.snapshot?.card {
    case .none:
      LabeledContent("Card", value: String(localized: "Checking..."))
    case .noCard:
      LabeledContent("Card", value: String(localized: "Not present"))
    case .sealed:
      LabeledContent("Card", value: String(localized: "Present over NFC"))
    case .unsupported:
      LabeledContent("Card", value: String(localized: "Not supported"))
    case .failed(let failure):
      LabeledContent("Card", value: Self.label(for: failure))
    // swiftlint:disable:next pattern_matching_keywords
    case .supported(let report, let name):
      LabeledContent(
        "Card",
        value: name ?? String(localized: "Finnish identity card")
      )
      LabeledContent("PIN1 attempts", value: Self.label(for: report.pin1))
      LabeledContent("PIN2 attempts", value: Self.label(for: report.pin2))
      LabeledContent("PUK attempts", value: Self.label(for: report.puk))
    }
  }

  private static func safariLabel(for snapshot: CardStatusSnapshot?) -> String {
    guard let snapshot else { return String(localized: "Checking...") }
    return snapshot.safariIdentityPresent
      ? String(localized: "Ready") : String(localized: "Not set up")
  }

  private static func label(for failure: CardStatusSnapshot.CaptureFailure) -> String {
    switch failure {
    case .cardUnreadable:
      String(localized: "Could not read - remove and present the card again")
    case .serviceUnavailable:
      String(localized: "Card support is unavailable")
    case .sessionUnavailable:
      String(localized: "In use by another app")
    }
  }

  private static func label(for outcome: RetryProbeOutcome) -> String {
    switch outcome {
    case .invalidated:
      return String(localized: "Invalidated - see recovery instructions")
    case .locked:
      return String(localized: "Locked - see recovery instructions")
    case .noInformation:
      return String(localized: "Unavailable")
    case .other(let statusWord):
      let status = String(statusWord, radix: Self.hexRadix, uppercase: true)
      return String(localized: "Unexpected answer (\(status))")
    case .remaining(let count):
      return String(
        localized: "\(Int(count.attemptsRemaining))/\(Int(RetryCount.pristineAllowance))")
    case .verified:
      return String(localized: "Verified")
    }
  }

  /// Publishes the stored CAN away from the launch path, then captures a
  /// passive status snapshot.
  private func load() async {
    Task.detached(priority: .utility) {
      CardCredentialStore.publishCardAccessNumberToDriver()
    }
    await model.refresh()
  }
}

#Preview {
  NavigationStack {
    StatusView()
  }
}
