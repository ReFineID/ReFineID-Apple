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
      // A grouped form, which is what the platform uses for exactly this
      // kind of list: labels aligned in their own column against their
      // values, no hand-drawn dividers, and no colons -- the alignment
      // is what separates a label from its value on this platform.
      Form {
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
        LabeledContent("Safari login (CTK)", value: Self.safariLabel(for: model.snapshot))
        transportRows
      }
      .formStyle(.grouped)
      .fixedSize(horizontal: false, vertical: true)
      // Labels in the secondary colour, values in the primary one, so a
      // row reads as one thing described by another rather than as two
      // words side by side.
      .labeledContentStyle(.automatic)
      .foregroundStyle(.primary)
      actionRows
    }
    // Each row keeps its natural width instead of compressing, so the
    // window's own minimum grows to whatever the longest line needs --
    // which is what stops the text being truncated to fit a window the
    // holder never chose. `windowResizability(.contentSize)` then makes
    // that minimum the smallest the window can be dragged to.
    .padding(Self.contentPadding)
    // The window cannot be made smaller than what it has to say. The
    // content keeps its natural height as well as its natural width, so
    // with `windowResizability(.contentSize)` the smallest the window
    // can be dragged to is the size that still shows every row -- there
    // is no useful window here that hides the card's status.
    .fixedSize(horizontal: false, vertical: true)
    .frame(minWidth: Self.minimumWidth, alignment: .leading)
    .task {
      // Off the main actor and off the launch path: this is a
      // synchronous call into `ctkd`, and `ctkd` is not always ready.
      Task.detached(priority: .utility) {
        CardCredentialStore.publishCardAccessNumberToDriver()
      }
      await model.refresh()
    }
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
    // One row: the thing a holder might press sits at the left, and the
    // instrument sits out of the way at the right.
    HStack {
      Button("Refresh") {
        Task { await model.refresh() }
      }
      .disabled(model.isRefreshing)
      Spacer()
      Button("Diagnostics") {
        showsDiagnostics = true
      }
      .accessibilityIdentifier("diagnosticsButton")
    }
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
      // The label carries the interface, because that is the difference
      // the holder can act on: a card on an antenna needs the number
      // below it, a card in the slot needs nothing.
      LabeledContent(
        "Card on NFC",
        value: String(localized: "Identity card")
      )
    case .unsupported:
      LabeledContent(
        "Card",
        value: String(localized: "Not a supported identity card")
      )
    case .failed(let failure):
      LabeledContent("Card", value: Self.label(for: failure))
    // The two linters want opposite things here: swiftlint's
    // pattern_matching_keywords asks for one `let` before the case,
    // swift-format's UseLetInEveryBoundCaseVariable asks for one per
    // binding. swift-format wins, because it is the formatter.
    // swiftlint:disable:next pattern_matching_keywords
    case .supported(let report, let name):
      LabeledContent(
        "Card on reader",
        value: name ?? String(localized: "Identity card")
      )
      LabeledContent("PIN1", value: Self.label(for: report.pin1))
      LabeledContent("PIN2", value: Self.label(for: report.pin2))
      LabeledContent("PUK", value: Self.label(for: report.puk))
    }
  }

  private static func safariLabel(for snapshot: CardStatusSnapshot?) -> String {
    guard let snapshot else { return String(localized: "Checking...") }
    return snapshot.safariIdentityPresent
      ? String(localized: "Ready") : String(localized: "Not available")
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
      // "5/5" rather than "5 attempts remaining": the denominator is the
      // fact worth showing, because 4 alone does not say how far from
      // trouble the card is.
      String(localized: "\(Int(count.attemptsRemaining))/\(Int(RetryCount.pristineAllowance))")
    case .verified:
      String(localized: "Verified in this session")
    }
  }
}

#Preview {
  StatusView()
}
