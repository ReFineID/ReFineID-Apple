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
        Button("Replace") {
          Task { await model.forgetCardAccessNumber() }
        }
      } else {
        entryRow
        Button("Save") {
          let entry = cardAccessNumberEntry
          cardAccessNumberEntry = ""
          Task { await model.saveCardAccessNumber(entry) }
        }
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
    #endif
  }

  /// PIN1: optional, and the same set-or-not treatment.
  @ViewBuilder private var pin1Section: some View {
    Section("PIN1") {
      if model.contents.hasPin1 {
        LabeledContent("PIN1", value: String(localized: "Set"))
        Button("Replace") {
          Task { await model.forgetPin1() }
        }
      } else {
        pin1Field
        Button("Save") {
          let entry = pin1Entry
          pin1Entry = ""
          Task { await model.savePin1(entry) }
        }
        .disabled(pin1Entry.count < Pin1.minimumDigitCount)
      }
    }
  }

  @ViewBuilder private var pin1Field: some View {
    #if os(iOS)
      SecureField("PIN1", text: $pin1Entry)
        .keyboardType(.numberPad)
    #else
      SecureField("PIN1", text: $pin1Entry)
    #endif
  }

  /// The hold that registers this card for Safari.
  @ViewBuilder private var primingSection: some View {
    #if os(iOS)
      Section("Safari") {
        NavigationLink("Register this card") {
          CardPrimingView()
        }
      }
    #endif
  }

  @ViewBuilder private var forgetSection: some View {
    Section {
      NavigationLink("Card status") {
        StatusView()
      }
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
