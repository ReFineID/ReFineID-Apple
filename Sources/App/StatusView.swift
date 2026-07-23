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
  private static let minimumWidth: CGFloat = 320

  @State private var model = CardStatusModel()

  private let versions = BundledVersions.read(from: .main)

  internal var body: some View {
    VStack(alignment: .leading, spacing: Self.rowSpacing) {
      Text(verbatim: "ReFineID")
        .font(.largeTitle.bold())
      Text("Use your Finnish identity card in Safari with a USB-C card reader.")
        .foregroundStyle(.secondary)
      Divider()
      LabeledContent(
        "Application",
        value: versions.application ?? String(localized: "Unknown")
      )
      LabeledContent(
        "Driver included",
        value: versions.driver ?? String(localized: "Not included")
      )
      Divider()
      LabeledContent(
        "Reader",
        value: model.snapshot?.readerName
          ?? String(localized: "Connect a card reader")
      )
      cardRows
      LabeledContent("Safari login", value: Self.safariLabel(for: model.snapshot))
      Button("Refresh") {
        Task { await model.refresh() }
      }
      .disabled(model.isRefreshing)
    }
    .padding(Self.contentPadding)
    .frame(minWidth: Self.minimumWidth)
    .task { await model.refresh() }
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
