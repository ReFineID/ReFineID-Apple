import CardCore
import SwiftUI

/// Where the holder stores the card access number, and chooses whether
/// this device may keep PIN1.
///
/// The screen never displays a stored secret. It reports only whether one
/// is present, and offers to replace or forget it: a holder who has
/// forgotten a value can set it again, and a screen that can show a PIN
/// is a screen that can leak one.
internal struct CardCredentialsView: View {
  private static let rowSpacing: CGFloat = 12

  @State private var model = CardCredentialsModel()
  @State private var cardAccessNumberEntry = ""
  @State private var pin1Entry = ""

  internal var body: some View {
    Form {
      cardAccessNumberSection
      pin1Section
      forgetSection
      if let failure = model.failure {
        Section {
          Text(failure)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Card details")
    .onAppear { model.refresh() }
  }

  /// Where the printed six digits are entered.
  @ViewBuilder private var cardAccessNumberSection: some View {
    Section {
      LabeledContent(
        "Card access number",
        value: model.contents.hasCardAccessNumber
          ? String(localized: "Stored")
          : String(localized: "Not stored"))
      SecureField("Six digits from the card", text: $cardAccessNumberEntry)
      Button("Save card access number") {
        let entry = cardAccessNumberEntry
        cardAccessNumberEntry = ""
        Task { await model.saveCardAccessNumber(entry) }
      }
      .disabled(cardAccessNumberEntry.count != CardAccessNumber.digitCount)
    } header: {
      Text("Card access number")
    } footer: {
      Text(
        """
        Printed on the front of the card. It lets this device open a \
        secure channel to the card over NFC, and it cannot authorize a \
        signature on its own. Stored on this iPhone only and never shown \
        again, but not behind Face ID: it is already printed on the card \
        you are holding.
        """)
    }
  }

  /// The opt-in that trades a prompt for convenience.
  @ViewBuilder private var pin1Section: some View {
    Section {
      LabeledContent(
        "PIN1",
        value: model.contents.hasPin1
          ? String(localized: "Stored on this device")
          : String(localized: "Asked for each time"))
      SecureField("PIN1", text: $pin1Entry)
      Button("Store PIN1 on this device") {
        let entry = pin1Entry
        pin1Entry = ""
        Task { await model.savePin1(entry) }
      }
      .disabled(pin1Entry.count < Pin1.minimumDigitCount)
      if model.contents.hasPin1 {
        Button("Forget PIN1", role: .destructive) {
          Task { await model.forgetPin1() }
        }
      }
    } header: {
      Text("PIN1")
    } footer: {
      Text(
        """
        Optional. Storing PIN1 lets a website sign you in without typing \
        it every time. It is kept under Face ID: reading it needs your \
        face at that moment, the device passcode alone will not do it, \
        and adding or changing a face or fingerprint clears it. It is \
        still a trade -- a signature can then be made with your card \
        without you typing anything -- so leave it off unless you want \
        that.
        """)
    }
  }

  /// The way back to a device that knows nothing.
  @ViewBuilder private var forgetSection: some View {
    Section {
      Button("Forget card details on this device", role: .destructive) {
        Task { await model.forgetEverything() }
      }
    } footer: {
      Text(
        """
        Card details are entered once and never shown again. They stay on \
        this iPhone: never in a backup, never restored onto another \
        device, never sent to iCloud.
        """)
    }
  }
}
