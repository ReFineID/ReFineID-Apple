// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// Setting the card up: the access number, PIN1, and the hold that
/// registers the card for Safari.
///
/// This is the screen that matters, so it is the one the app opens on.
/// Development builds keep technical state behind the Diagnostics row.
///
/// The two credentials and the action they enable form one operation.
/// Individual replacement controls would imply that they are independent;
/// starting over is instead the explicit forget action below.
///
/// Every control a test drives carries an accessibility identifier, and
/// the register of them is `UITestIdentifiers` in `Tests/ReFineIDUITests`.
/// Identifiers rather than labels, because a label is localized: a device
/// set to Finnish would otherwise fail every query for a reason that has
/// nothing to do with the card. They cost nothing at runtime and they are
/// what VoiceOver already wants.
internal struct CardCredentialsView: View {
  private static let sectionSpacing: CGFloat = 24
  private static let footerPadding: CGFloat = 12

  @State private var model = CardCredentialsModel()
  @State private var cardAccessNumberEntry = ""
  @State private var pin1Entry = ""
  @State private var isScanning = false
  @State private var scannerTorchEnabled = false
  @State private var showsForgetConfirmation = false
  @State private var registrationReset = false
  @State private var isRegistered = false
  @FocusState private var isPin1FieldFocused: Bool

  #if canImport(CoreNFC) && os(iOS)
    /// The priming model lives here, above everything a hold hides.
    @State private var primingModel = CardPrimingModel()
  #endif

  /// The PIN is valid for storage only inside the card's documented range.
  private var isPin1EntryComplete: Bool {
    pin1Entry.count >= Pin1.minimumDigitCount
      && pin1Entry.count <= Pin1.maximumDigitCount
  }

  /// Whether a card is being held against the phone right now.
  ///
  /// Read from the model the parent owns, so it cannot be stranded by
  /// the very views a hold hides.
  private var isHolding: Bool {
    #if canImport(CoreNFC) && os(iOS)
      return primingModel.isRunning
    #else
      return false
    #endif
  }

  /// Whether this device has an antenna to set an identity with.
  ///
  /// An iPad has none, and runs the same binary as an iPhone. Offering
  /// it a card setup it can never finish -- two fields to fill and a
  /// button that only ever stays grey -- describes the app as broken
  /// rather than the device as different.
  private var offersNearField: Bool {
    #if canImport(CoreNFC) && os(iOS)
      return primingModel.allowsNearField
    #else
      return true
    #endif
  }

  /// Both credentials must be usable before minting starts.
  ///
  /// A field left empty falls back to what is stored; a field with
  /// something in it has to be complete, because a half-typed
  /// replacement is a replacement the holder is still writing.
  private var canPrepareIdentity: Bool {
    let numberReady =
      cardAccessNumberEntry.isEmpty
      ? model.contents.hasCardAccessNumber
      : cardAccessNumberEntry.count == CardAccessNumber.digitCount
    let pinReady = pin1Entry.isEmpty ? model.contents.hasPin1 : isPin1EntryComplete
    return numberReady && pinReady
  }

  internal var body: some View {
    Form {
      // While the card is against the phone, Apple's panel is the
      // screen and everything under it is furniture behind frosted
      // glass. Clearing it leaves the app's name, which is all a
      // dimmed backdrop can usefully say.
      if isHolding {
        EmptyView()
      } else if !offersNearField {
        // No antenna: a reader is the only way in, and saying so is the
        // whole screen. There is nothing to store first -- a card in a
        // contact reader needs no access number.
        readerOnlySection
      } else if isRegistered {
        // A set identity replaces the whole setup: nothing about it is
        // left to configure, so nothing about configuring it is shown.
        identitySection
      } else {
        createIdentitySection
      }
      if let failure = model.failure {
        Section {
          Text(failure)
            .foregroundStyle(.red)
        }
      }
      // Only an identity is worth a destructive action. Stored
      // credentials are not: the fields above are editable until an
      // identity exists, so a wrong number is corrected by typing over
      // it rather than by forgetting anything.
      if isRegistered, !isHolding, offersNearField {
        forgetSection
      }
    }
    #if os(iOS)
      .listSectionSpacing(Self.sectionSpacing)
      .navigationTitle("ReFineID")
      .navigationBarTitleDisplayMode(.large)
    #endif
    // Development-only, pinned under every product control: a shipped
    // build has no diagnostics and no logging at all.
    #if DEBUG
      .safeAreaInset(edge: .bottom) { diagnosticsFooter }
    #endif
    .onAppear {
      model.refresh()
      refreshRegistration()
      showStoredCardAccessNumber()
    }
    .onChange(of: isRegistered) { _, registered in
      // A set identity ends the fields' job; nothing they held is worth
      // keeping in memory once the setup they belonged to is over.
      if registered {
        clearEntries()
      }
    }
    .onChange(of: model.contents) { _, _ in
      // A hold that stored the number and then broke leaves the field
      // as it was. Seeding again here puts the stored number back in
      // front of the holder, which is where a wrong one gets noticed.
      showStoredCardAccessNumber()
    }
    #if os(iOS)
      .sheet(isPresented: $isScanning) {
        scannerSheet
      }
    #endif
    .alert(
      "Forget identity?",
      isPresented: $showsForgetConfirmation
    ) {
      Button("Forget", role: .destructive) {
        model.forgetEverything()
        registrationReset.toggle()
        isRegistered = false
        clearEntries()
      }
    }
  }

  /// What a device with no antenna is told instead of a setup form.
  private var readerOnlySection: some View {
    Section {
      Text("Connect a card reader and insert your card.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("readerOnlyNotice")
    }
  }

  /// The finished state: who the stored card says they are.
  ///
  /// The same row a connected reader shows, read from the stored prime
  /// rather than from the token: a registered card's token has to be
  /// minted before the keychain can answer for it, and minting one over
  /// near field opens a scan sheet on a screen nobody asked to scan
  /// from. A check mark stands in when the name will not parse, because
  /// the identity is set either way and that is what this row reports.
  private var identitySection: some View {
    Section {
      LabeledContent("Person") {
        if let holder = primedHolder {
          Text(holder)
            .textSelection(.enabled)
        } else {
          Image(systemName: "checkmark")
            .foregroundStyle(.green)
            .accessibilityLabel("Set")
        }
      }
      .accessibilityIdentifier("identityStatus")
    }
  }

  /// Who the primed card names, or nil when no name can be read.
  private var primedHolder: String? {
    PrimeStore.primedHolderNames().first
  }

  /// One operation, in its actual order: credentials and then minting.
  @ViewBuilder private var createIdentitySection: some View {
    Section("Enable authentication") {
      cardAccessNumberRow
      pin1Row
    }
    #if os(iOS)
      // Its own section and its own visual weight: the credential rows
      // collect input, this is the screen's one primary action.
      Section {
        CardRegistrationSections(
          canPrepareCredentials: canPrepareIdentity,
          prepareCredentials: prepareIdentity,
          isRegistered: $isRegistered,
          model: primingModel
        )
        .id(registrationReset)
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    #endif
  }

  /// The six printed digits, with the QR scanner beside them.
  ///
  /// Editable for as long as there is no identity. A setup that breaks
  /// half way is very often a mistyped number, and a field that turned
  /// into a checkmark the moment it was stored left the holder with no
  /// way to correct it short of forgetting everything.
  @ViewBuilder private var cardAccessNumberRow: some View {
    #if os(iOS)
      HStack {
        SecureField("Card Access Number (CAN)", text: $cardAccessNumberEntry)
          .keyboardType(.numberPad)
          .accessibilityIdentifier("cardAccessNumberField")
          .onChange(of: cardAccessNumberEntry) { _, typed in
            cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
          }
        if CardAccessNumberScanner.isAvailable {
          Button {
            scannerTorchEnabled = false
            isScanning = true
          } label: {
            Label("Scan", systemImage: "camera")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
        }
      }
    #else
      SecureField("Card Access Number (CAN)", text: $cardAccessNumberEntry)
        .accessibilityIdentifier("cardAccessNumberField")
        .onChange(of: cardAccessNumberEntry) { _, typed in
          cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
        }
    #endif
  }

  /// PIN1 entry, editable until the IDENTITY is set.
  ///
  /// Not until a PIN is stored -- until the identity is. A stored PIN
  /// that turns out to be wrong is one of the two reasons a setup dies,
  /// and a field that locked itself the moment it was stored left no way
  /// to correct it. The field stays; typing replaces what is kept.
  ///
  /// It carries no stored mark, because a mark beside an empty box
  /// claims the box is filled. A stored PIN is never read back, so the
  /// box is empty whether or not one is kept.
  @ViewBuilder private var pin1Row: some View {
    SecureField("Basic Code (PIN1)", text: $pin1Entry)
      #if os(iOS)
        .keyboardType(.numberPad)
        .textInputAutocapitalization(.never)
      #endif
      .autocorrectionDisabled()
      .focused($isPin1FieldFocused)
      .accessibilityIdentifier("pin1Field")
      .onChange(of: pin1Entry) { _, typed in
        pin1Entry = LimitedDigits.pin1(typed)
      }
  }

  #if DEBUG
    private var diagnosticsFooter: some View {
      NavigationLink {
        DiagnosticsView()
      } label: {
        Label("Diagnostics", systemImage: "stethoscope")
      }
      .accessibilityIdentifier("diagnosticsButton")
      .padding(.vertical, Self.footerPadding)
      .frame(maxWidth: .infinity)
      .background(.bar)
    }
  #endif

  /// The destructive action, shown only when there is an identity.
  ///
  /// It removes everything the device knows about the card, which is
  /// worth confirming. Before an identity exists there is nothing here
  /// that needs removing rather than overwriting.
  private var forgetSection: some View {
    Section {
      Button("Forget identity", role: .destructive) {
        showsForgetConfirmation = true
      }
      .accessibilityIdentifier("forgetCardIdentityButton")
    }
  }

  #if os(iOS)
    /// The camera, framed so it can be dismissed.
    private var scannerSheet: some View {
      ScannerSheet(
        torchEnabled: $scannerTorchEnabled,
        isScanning: $isScanning
      ) { digits in
        cardAccessNumberEntry = digits
      }
    }
  #endif

  /// Puts a stored card access number back in its field.
  ///
  /// The number is printed on the card face and is the holder's to see,
  /// so a stored one is shown rather than asserted by a mark beside an
  /// empty box. Seeing the digits is also the only way to notice that
  /// the stored ones are wrong, which is the usual reason a setup breaks
  /// half way.
  private func showStoredCardAccessNumber() {
    guard cardAccessNumberEntry.isEmpty, let stored = model.storedCardAccessNumber else {
      return
    }
    cardAccessNumberEntry = stored
  }

  /// Reads the persistent registration state, on the platform that has it.
  private func refreshRegistration() {
    #if canImport(CoreNFC) && os(iOS)
      isRegistered = CardRegistrationSections.hasRegisteredIdentity
    #endif
  }

  /// Stores the entered pair immediately before the NFC operation.
  ///
  /// A typed value wins over a stored one. The fields stay editable
  /// until an identity exists precisely so a mistyped number can be
  /// corrected, and a correction that the store ignored because
  /// something was already kept would be worse than no field at all. An
  /// empty field means the holder is content with what is stored.
  @MainActor
  private func prepareIdentity() -> Bool {
    let accessNumber = cardAccessNumberEntry.isEmpty ? nil : cardAccessNumberEntry
    let pin1 = pin1Entry.isEmpty ? nil : pin1Entry

    // The fields keep what was typed. Emptying them here was what left a
    // holder unable to see, check or correct a PIN after a hold that
    // failed -- the one moment both are worth looking at. They are
    // cleared when the identity is set and when the card is forgotten,
    // which is when there is nothing left for them to be about.
    isPin1FieldFocused = false

    return model.prepareIdentity(
      cardAccessNumber: accessNumber,
      pin1: pin1)
  }

  /// Empties both fields once they have nothing left to describe.
  private func clearEntries() {
    cardAccessNumberEntry = ""
    pin1Entry = ""
    isPin1FieldFocused = false
  }
}
