import CardCore
import SwiftUI

/// Setting the card up: the access number, PIN1, and the hold that
/// registers the card for Safari.
///
/// This is the screen that matters, so it is the one the app opens on.
/// What the card reports about itself is diagnostic and lives behind the
/// status screen.
///
/// Nothing stored is ever shown again. A value is either set or not, and
/// a set value can be replaced or forgotten. There is no explanatory
/// text: a setup screen that needs paragraphs to be understood is the
/// wrong screen.
///
/// Every control a test drives carries an accessibility identifier, and
/// the register of them is `UITestIdentifiers` in `Tests/ReFineIDUITests`.
/// Identifiers rather than labels, because a label is localized: a device
/// set to Finnish would otherwise fail every query for a reason that has
/// nothing to do with the card. They cost nothing at runtime and they are
/// what VoiceOver already wants.
internal struct CardCredentialsView: View {
  @State private var model = CardCredentialsModel()
  @State private var cardAccessNumberEntry = ""
  @State private var pin1Entry = ""
  @State private var isScanning = false

  internal var body: some View {
    Form {
      cardAccessNumberSection
      pin1Section
      if model.contents.hasCardAccessNumber {
        primingSection
      }
      if let failure = model.failure {
        Section {
          Text(failure)
            .foregroundStyle(.red)
        }
      }
      forgetSection
    }
    .navigationTitle("Set up your card")
    .onAppear { model.refresh() }
    #if os(iOS)
      .sheet(isPresented: $isScanning) {
        scannerSheet
      }
    #endif
  }

  /// The six printed digits: an entry row while unset, one line once set.
  @ViewBuilder private var cardAccessNumberSection: some View {
    Section("Card access number") {
      if model.contents.hasCardAccessNumber {
        LabeledContent("Card access number", value: String(localized: "Set"))
          .accessibilityIdentifier("cardAccessNumberStatus")
        Button("Replace") {
          Task { await model.forgetCardAccessNumber() }
        }
        .accessibilityIdentifier("replaceCardAccessNumber")
      } else {
        entryRow
        Button("Save") {
          let entry = cardAccessNumberEntry
          cardAccessNumberEntry = ""
          Task { await model.saveCardAccessNumber(entry) }
        }
        .accessibilityIdentifier("saveCardAccessNumber")
        .disabled(cardAccessNumberEntry.count != CardAccessNumber.digitCount)
      }
    }
  }

  /// The digits field, with the camera beside it where there is one.
  @ViewBuilder private var entryRow: some View {
    #if os(iOS)
      HStack {
        TextField("Six digits", text: $cardAccessNumberEntry)
          .keyboardType(.numberPad)
          .accessibilityIdentifier("cardAccessNumberField")
        if CardAccessNumberScanner.isAvailable {
          Button {
            isScanning = true
          } label: {
            Label("Scan", systemImage: "camera")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
        }
      }
    #else
      TextField("Six digits", text: $cardAccessNumberEntry)
        .accessibilityIdentifier("cardAccessNumberField")
    #endif
  }

  /// PIN1: optional, and the same set-or-not treatment.
  @ViewBuilder private var pin1Section: some View {
    Section("PIN1") {
      if model.contents.hasPin1 {
        LabeledContent("PIN1", value: String(localized: "Set"))
          .accessibilityIdentifier("pin1Status")
        Button("Replace") {
          Task { await model.forgetPin1() }
        }
        .accessibilityIdentifier("replacePin1")
      } else {
        pin1Field
        Button("Save") {
          let entry = pin1Entry
          pin1Entry = ""
          Task { await model.savePin1(entry) }
        }
        .accessibilityIdentifier("savePin1")
        .disabled(pin1Entry.count < Pin1.minimumDigitCount)
      }
    }
  }

  @ViewBuilder private var pin1Field: some View {
    #if os(iOS)
      SecureField("PIN1", text: $pin1Entry)
        .keyboardType(.numberPad)
        .accessibilityIdentifier("pin1Field")
    #else
      SecureField("PIN1", text: $pin1Entry)
        .accessibilityIdentifier("pin1Field")
    #endif
  }

  /// The hold that registers this card for Safari.
  @ViewBuilder private var primingSection: some View {
    #if os(iOS)
      Section("Safari") {
        NavigationLink("Register this card") {
          CardPrimingView()
        }
        .accessibilityIdentifier("registerCardLink")
      }
    #endif
  }

  @ViewBuilder private var forgetSection: some View {
    Section {
      NavigationLink("Card status") {
        StatusView()
      }
      .accessibilityIdentifier("cardStatusLink")
      Button("Forget this card", role: .destructive) {
        Task { await model.forgetEverything() }
      }
      .disabled(!model.contents.hasCardAccessNumber && !model.contents.hasPin1)
    }
  }

  #if os(iOS)
    /// The camera, framed so it can be dismissed.
    @ViewBuilder private var scannerSheet: some View {
      NavigationStack {
        CardAccessNumberScanner { digits in
          cardAccessNumberEntry = digits
          isScanning = false
        }
        .ignoresSafeArea()
        .navigationTitle("Point at the card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { isScanning = false }
          }
        }
      }
    }
  #endif
}
