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

  /// Smallest useful desktop window; a phone must instead accept its
  /// proposed width or this wider frame is centred and clipped on both
  /// sides.
  #if os(macOS)
    private static let minimumWidth: CGFloat? = 560
  #else
    private static let minimumWidth: CGFloat? = nil
  #endif

  /// Wide enough for six digits with room to see them.
  private static let entryWidth: CGFloat = 120

  @State private var model = CardStatusModel()

  @State private var transports = TransportPreferences()

  /// Whether the diagnostics capture is on screen.
  @State private var showsDiagnostics = false

  /// The stored card access number, and what may be done about it.
  @State private var credentials = CardCredentialsModel()

  /// What the holder is typing, while they are typing it.
  @State private var cardAccessNumberEntry = ""

  /// Whether the entry is the six digits a card access number is.
  private var isEnteredNumberComplete: Bool {
    cardAccessNumberEntry.count == CardAccessNumber.digitCount
  }

  /// Whether the card is present and readable but the system is not
  /// offering it, which is the one fault a holder can clear themselves.
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
        cardTypeRow
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
      // The one instruction that always works, and the only one this app
      // can give. The system asks a driver about a card when the card
      // arrives, so a card already sitting in the reader when its access
      // number was entered is never asked about again -- and nothing
      // inside a sandbox can make the system look a second time. So the
      // holder is told plainly, rather than left with a row saying the
      // login is unavailable and no way to change it.
      if needsReseating {
        Label(
          "Remove the card and put it back, so the system reads it again.",
          systemImage: "arrow.counterclockwise"
        )
        .foregroundStyle(.orange)
      }
      actionRows
    }
    .padding(Self.contentPadding)
    // On macOS the window cannot be made narrower than the status it has
    // to show. On iOS the nil minimum accepts the screen width instead;
    // imposing the desktop width there shifts both edges off-screen.
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
            credentials.forgetCardAccessNumber()
          }
          .accessibilityIdentifier("replaceCardAccessNumber")
        }
      }
    } else {
      LabeledContent("Card access number") {
        HStack(spacing: Self.rowSpacing) {
          // Hidden, not absent: inside a form a text field draws its
          // own label to the left of itself, so the placeholder ends up
          // as a second label beside the row's own -- wrapped onto two
          // lines and crowding the field it belongs to. The label still
          // exists for anyone reading the screen aloud.
          TextField("CAN", text: $cardAccessNumberEntry)
            .labelsHidden()
            .accessibilityIdentifier("cardAccessNumberField")
            .frame(width: Self.entryWidth)
            .onSubmit { save() }
          Button("Save") { save() }
            .accessibilityIdentifier("saveCardAccessNumber")
            .disabled(!isEnteredNumberComplete)
        }
      }
    }
    if let failure = credentials.failure {
      Text(failure)
        .font(.footnote)
        .foregroundStyle(.red)
    }
  }

  /// What the card is, when its answer to reset says so.
  ///
  /// A generation without an exact match is shown as the generation and
  /// says so, rather than being rounded to the nearest documented model:
  /// the table has a date on it and cards are issued after that date.
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

  /// Stores what was typed, then re-reads the card.
  ///
  /// Also what the return key does, because a six-digit field is a thing
  /// people type and press return on.
  private func save() {
    guard isEnteredNumberComplete else { return }
    let entry = cardAccessNumberEntry
    cardAccessNumberEntry = ""
    credentials.saveCardAccessNumber(entry, boundToSerial: nil)
    Task {
      await model.refresh()
    }
  }
}

#Preview {
  StatusView()
}
