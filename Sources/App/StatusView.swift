import CardCore
import SwiftUI

/// The status window: versions, reader, card, and credential counters.
///
/// Wording is deliberate and consumer-friendly: the driver is "included"
/// (no public API proves enablement), counters come from
/// side-effect-free probes, and a blocked credential points at recovery
/// without alarm. All user-facing strings localize through
/// `Localizable.xcstrings` (English, Finnish, Swedish).
internal struct StatusView: View {
  private static let rowSpacing: CGFloat = 12
  private static let contentPadding: CGFloat = 24
  private static let minimumWidth: CGFloat = 560

  /// Wide enough for six digits and no wider.
  private static let entryWidth: CGFloat = 90

  @State private var model = CardStatusModel()

  @State private var transports = TransportPreferences()

  /// Whether the diagnostics capture is on screen.
  @State private var showsDiagnostics = false

  /// The stored card access number, and what may be done about it.
  @State private var credentials = CardCredentialsModel()

  /// What the holder is typing, while they are typing it.
  @State private var cardAccessNumberEntry = ""

  internal var body: some View {
    VStack(alignment: .leading, spacing: Self.rowSpacing) {
      Text(verbatim: "ReFineID")
        .font(.largeTitle.bold())
      Text("Finnish identity card middleware")
        .foregroundStyle(.secondary)
      Divider()
      LabeledContent(
        "Reader",
        value: model.snapshot?.readerName
          ?? String(localized: "Connect a card reader")
      )
      cardRows
      // Only where it is needed. A card in a contact slot answers
      // without one, so a row saying the number is stored is a setting
      // about nothing -- it belongs on screen when a card is sitting on
      // an antenna, sealed, waiting for exactly this.
      if case .sealed = model.snapshot?.card {
        cardAccessNumberRow
      }
      LabeledContent("Safari login", value: Self.safariLabel(for: model.snapshot))
      transportRows
      actionRows
    }
    // Each row keeps its natural width instead of compressing, so the
    // window's own minimum grows to whatever the longest line needs --
    // which is what stops the text being truncated to fit a window the
    // holder never chose. `windowResizability(.contentSize)` then makes
    // that minimum the smallest the window can be dragged to.
    .fixedSize(horizontal: true, vertical: false)
    .padding(Self.contentPadding)
    .frame(minWidth: Self.minimumWidth, alignment: .leading)
    .task { await model.refresh() }
    .sheet(isPresented: $showsDiagnostics) { diagnosticsSheet }
  }

  /// What the holder can do from here.
  ///
  /// Setting the card up is reachable on the Mac as well now. It was
  /// iOS-only while a card access number was thought to matter only on
  /// the phone's own antenna -- but a desk reader has an antenna too,
  /// and a card resting on it is sealed in exactly the same way, so a
  /// Mac that cannot be told the number cannot use that card at all.
  ///
  /// Diagnostics is deliberately reachable from here rather than hidden
  /// behind a launch flag: when a login fails on a device that is not
  /// plugged into anything, the only instrument left is the one the
  /// holder can open.
  @ViewBuilder private var actionRows: some View {
    Button("Refresh") {
      Task { await model.refresh() }
    }
    .disabled(model.isRefreshing)
    Button("Diagnostics") {
      showsDiagnostics = true
    }
    .accessibilityIdentifier("diagnosticsButton")
  }

  /// The capture, in its own stack so it has a title bar to dismiss from
  /// on both platforms.
  @ViewBuilder private var diagnosticsSheet: some View {
    NavigationStack {
      DiagnosticsView()
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { showsDiagnostics = false }
          }
        }
    }
  }

  /// Transport switches.
  ///
  /// The near-field control is absent, not disabled, where the platform
  /// has no antenna: a Mac cannot be talked into growing one. Each
  /// toggle refuses to turn off the last enabled transport, so the app
  /// always retains some way of reaching a card.
  @ViewBuilder private var transportRows: some View {
    if SupportedCardTransports.offersNearField {
      Divider()
      // The phone's own antenna comes first: it needs no hardware, so
      // it is what most holders will use.
      Toggle(
        "Use phone as reader",
        isOn: Binding(
          get: { transports.permits(.nearField) },
          set: { transports.setPermitted($0, for: .nearField) }
        )
      )
      Toggle(
        "Use a connected card reader",
        isOn: Binding(
          get: { transports.permits(.reader) },
          set: { transports.setPermitted($0, for: .reader) }
        )
      )
      if transports.lastWriteFailed {
        Text("Keep at least one way to read the card switched on.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// The six printed digits: an entry row until they are stored, one
  /// line afterwards.
  ///
  /// On the one screen this app has, rather than behind a button. It is
  /// the only thing a holder must type, it is needed the moment a card
  /// is on an antenna, and a screen that says "enter the card access
  /// number" and then does not offer anywhere to enter it is worse than
  /// not saying it.
  @ViewBuilder private var cardAccessNumberRow: some View {
    if credentials.contents.hasCardAccessNumber {
      LabeledContent("Card access number") {
        HStack(spacing: Self.rowSpacing) {
          Text("Stored")
          Button("Replace") {
            Task { await credentials.forgetCardAccessNumber() }
          }
          .accessibilityIdentifier("replaceCardAccessNumber")
        }
      }
    } else {
      LabeledContent("Card access number") {
        HStack(spacing: Self.rowSpacing) {
          TextField("Six digits", text: $cardAccessNumberEntry)
            .accessibilityIdentifier("cardAccessNumberField")
            .frame(width: Self.entryWidth)
          Button("Save") {
            let entry = cardAccessNumberEntry
            cardAccessNumberEntry = ""
            Task {
              await credentials.saveCardAccessNumber(entry)
              await model.refresh()
            }
          }
          .accessibilityIdentifier("saveCardAccessNumber")
          .disabled(cardAccessNumberEntry.count != CardAccessNumber.digitCount)
        }
      }
    }
    if let failure = credentials.failure {
      Text(failure)
        .font(.footnote)
        .foregroundStyle(.red)
    }
  }

  @ViewBuilder private var cardRows: some View {
    switch model.snapshot?.card {
    case .none:
      LabeledContent("Card", value: String(localized: "Checking..."))
    case .noCard:
      LabeledContent(
        "Card",
        value: String(localized: "Insert your identity card")
      )
    case .sealed:
      LabeledContent(
        "Card",
        value: String(localized: "Identity card on the contactless interface")
      )
    case .unsupported:
      LabeledContent(
        "Card",
        value: String(localized: "Not a supported identity card")
      )
    case .failed(let failure):
      LabeledContent("Card", value: Self.label(for: failure))
    case .supported(let report):
      LabeledContent(
        "Card",
        value: String(localized: "Identity card recognized")
      )
      LabeledContent("PIN1", value: Self.label(for: report.pin1))
      LabeledContent("PIN2", value: Self.label(for: report.pin2))
      LabeledContent("PUK", value: Self.label(for: report.puk))
    }
  }

  private static func safariLabel(for snapshot: CardStatusSnapshot?) -> String {
    guard let snapshot else { return String(localized: "Checking...") }
    if snapshot.safariIdentityPresent {
      return String(localized: "Ready - the card is available to Safari")
    }
    return String(
      localized: "Not available - this version does not yet publish the card"
    )
  }

  private static func hexLabel(_ value: UInt16) -> String {
    let hexRadix = 16
    return String(value, radix: hexRadix, uppercase: true)
  }

  private static func label(for failure: CardStatusSnapshot.CaptureFailure) -> String {
    switch failure {
    case .cardUnreadable:
      String(
        localized: "Could not read the card - remove it and insert it again"
      )
    case .serviceUnavailable:
      String(
        localized: "Smart-card support is unavailable on this device"
      )
    case .sessionUnavailable:
      String(
        localized: "The card is in use by another app - try again"
      )
    }
  }

  private static func label(for outcome: RetryProbeOutcome) -> String {
    switch outcome {
    case .invalidated:
      String(localized: "Invalidated - see recovery instructions")
    case .locked:
      String(localized: "Locked - see recovery instructions")
    case .noInformation:
      String(localized: "Status unavailable")
    case .other(let statusWord):
      String(
        localized: "Unexpected answer from the card (\(Self.hexLabel(statusWord)))"
      )
    case .remaining(let count):
      String(localized: "\(Int(count.attemptsRemaining)) attempts remaining")
    case .verified:
      String(localized: "Verified in this session")
    }
  }
}

#Preview {
  StatusView()
}
