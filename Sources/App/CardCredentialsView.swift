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
  private enum Destination: Hashable {
    case activation
    case pinManagement
  }

  private static let sectionSpacing: CGFloat = 24

  @State private var model = CardCredentialsModel()
  @State private var cardAccessNumberEntry = ""
  @State private var pin1Entry = ""
  @State private var isScanning = false
  @State private var scannerTorchEnabled = false
  @State private var showsForgetConfirmation = false
  @State private var registrationReset = false
  @State private var isRegistered = false
  @State private var isLandscapeLayout = false
  @State private var activationScheme: ActivationScheme?
  @State private var activationNeeds: CardActivationNeeds?
  @State private var destination: Destination?
  @State private var demonstrationConnected = false
  @FocusState private var isCardAccessNumberFieldFocused: Bool
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

  /// The point at which operations using the printed card number can be
  /// offered. Until all six digits exist, PIN1 has no card to belong to.
  private var isCardAccessNumberEntryComplete: Bool {
    cardAccessNumberEntry.count == CardAccessNumber.digitCount
  }

  /// CAN receives initial focus only while it is the screen's sole input.
  private var shouldFocusCardAccessNumber: Bool {
    !hasIdentity
      && offersNearField
      && !isHolding
      && !isCardAccessNumberEntryComplete
  }

  /// The visible CAN handed to PIN management, only when complete.
  ///
  /// The setup field is also where a stored CAN is shown, so there is
  /// one source of truth and the management screen never has to ask for
  /// the same printed number again.
  internal var managementCardAccessNumber: String? {
    !isDemonstration
      && model.contents.hasCardAccessNumber
      && isCardAccessNumberEntryComplete
      ? cardAccessNumberEntry
      : nil
  }

  /// Disclosure follows a validated connection, never digit count alone.
  private var hasConfiguredCard: Bool {
    model.contents.hasCardAccessNumber || (isDemonstration && demonstrationConnected)
  }

  /// Whether this launch is demonstrating the flow without a card.
  ///
  /// Every branch below that reads it is a place where the screen
  /// deliberately does not touch the card, the keychain or the system.
  private var isDemonstration: Bool {
    #if os(iOS)
      return DemoMode.shared.isActive
    #else
      return false
    #endif
  }

  /// The holder of the complete identity to show instead of a setup form.
  ///
  /// A demonstration answers from ``DemoMode``, which holds its identity
  /// for the process and writes nothing; everything else answers from
  /// what the device actually registered. A registration that cannot name
  /// its holder is incomplete and must never render as a finished identity.
  private var identityHolder: String? {
    #if os(iOS)
      if isDemonstration {
        return DemoMode.shared.hasIdentity ? DemoMode.holderName : nil
      }
    #endif
    guard isRegistered else { return nil }
    return PrimeStore.primedHolderNames().first
  }

  /// Whether there is a complete, displayable identity.
  private var hasIdentity: Bool {
    identityHolder != nil
  }

  /// Whether a card is being held against the phone right now.
  ///
  /// Read from the model the parent owns, so it cannot be stranded by
  /// the very views a hold hides.
  private var isHolding: Bool {
    #if canImport(CoreNFC) && os(iOS)
      return model.isConnecting || primingModel.isRunning || DemoMode.shared.isHolding
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
      return primingModel.allowsNearField || isDemonstration
    #else
      return true
    #endif
  }

  /// Both credentials must be usable before minting starts.
  ///
  /// A field left empty falls back to what is stored; a field with
  /// something in it has to be complete, because a half-typed
  /// replacement is a replacement the holder is still writing.
  ///
  /// A demonstration has no stored pair to fall back to and no card to
  /// check either entry against, so it asks only that both were typed.
  private var canPrepareIdentity: Bool {
    if isDemonstration {
      return !cardAccessNumberEntry.isEmpty && !pin1Entry.isEmpty
    }
    return model.contents.hasCardAccessNumber && isPin1EntryComplete
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
      } else if let identityHolder {
        // A set identity replaces the whole setup: nothing about it is
        // left to configure, so nothing about configuring it is shown.
        CardIdentitySection(holder: identityHolder)
      } else {
        createIdentitySection
      }
      #if !os(iOS)
        if !isHolding {
          managementSection
        }
      #endif
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
      if hasIdentity, !isHolding, offersNearField {
        forgetSection
      }
    }
    #if os(iOS)
      .id(isLandscapeLayout)
      .listSectionSpacing(Self.sectionSpacing)
      .navigationTitle("ReFineID")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        if managementCardAccessNumber != nil, !isHolding {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              destination = .pinManagement
            } label: {
              Image(systemName: "key")
                .accessibilityLabel(Text("Change or Reset PINs"))
            }
            .accessibilityIdentifier("manageCard")
          }
        }
      }
      .navigationDestination(item: $destination) { destination in
        switch destination {
        case .activation:
#if DEBUG
          let _ = DebugConsole.emit("navigation-destination: activation")
#endif
          if let activationScheme, let activationNeeds {
            CardManagementView(
              activationRequired: true,
              cardAccessNumber: cardAccessNumberEntry,
              activationScheme: activationScheme,
              activationNeeds: activationNeeds,
              onActivationSucceeded: activationSucceeded)
              .id(Destination.activation)
          }
        case .pinManagement:
#if DEBUG
          let _ = DebugConsole.emit("navigation-destination: PIN management")
#endif
          CardManagementView(
            cardAccessNumber: managementCardAccessNumber)
            .id(Destination.pinManagement)
        }
      }
      .onGeometryChange(for: Bool.self) { geometry in
        geometry.size.width > geometry.size.height
      } action: { isLandscape in
        isLandscapeLayout = isLandscape
      }
    #endif
    // Pinned under every product control: what this run is, when it is
    // anything but the shipped product doing its job.
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 0) {
        if !isCardAccessNumberFieldFocused, !isPin1FieldFocused {
          CardSetupFooter(isDemonstration: isDemonstration)
        }
      }
    }
    .onAppear {
      model.refresh()
      refreshRegistration()
      showStoredCardAccessNumber()
    }
    .task(id: shouldFocusCardAccessNumber) {
      guard shouldFocusCardAccessNumber else { return }
      // Let the conditional Form row enter the hierarchy before asking
      // SwiftUI to make it first responder. This yields an event turn;
      // it is not a time-based delay.
      await Task.yield()
      guard shouldFocusCardAccessNumber else { return }
      isCardAccessNumberFieldFocused = true
    }
    .onChange(of: hasIdentity) { _, registered in
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
    .onChange(of: isCardAccessNumberEntryComplete) { _, complete in
      // A PIN entered for one complete CAN must not survive while that
      // CAN is erased or replaced. It reappears only after the new card
      // number is complete and the holder enters its PIN deliberately.
      if !complete {
        pin1Entry = ""
        isPin1FieldFocused = false
        demonstrationConnected = false
      }
    }
    .onChange(of: cardAccessNumberEntry) { _, entered in
      if !entered.isEmpty {
        model.clearFailure()
      }
      guard entered.isEmpty,
        !isDemonstration,
        model.contents.hasCardAccessNumber
      else { return }
      model.forgetEverything()
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
        // A demonstration has nothing stored to forget: dropping its
        // test person returns the screen to the setup form, and the run
        // stays a demonstration.
        #if os(iOS)
          if isDemonstration {
            DemoMode.shared.forgetIdentity()
            clearEntries()
            return
          }
        #endif
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

  /// One operation, in its actual order: credentials and then minting.
  @ViewBuilder private var createIdentitySection: some View {
    Section("Connect Identity Card Wirelessly") {
      cardAccessNumberRow
    }
    if hasConfiguredCard {
      Section("Enable authentication") {
        pin1Row
      }
      #if os(iOS)
        // Its own section and its own visual weight: the credential rows
        // collect input, this is the screen's one primary action.
        Section {
          CardRegistrationSections(
            canPrepareCredentials: canPrepareIdentity,
            isDemonstration: isDemonstration,
            enteredPin1: enteredPin1,
            storeVerifiedPin1: model.savePin1,
            clearPin1Entry: clearPin1Entry,
            isRegistered: $isRegistered,
            model: primingModel
          )
          .id(registrationReset)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      #endif
    } else {
      Section {
        Button {
          connectIdentityCard()
        } label: {
          Text("Connect")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isCardAccessNumberEntryComplete || model.isConnecting)
        .accessibilityIdentifier("connectCard")
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    }
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
        TextField("Card Access Number (CAN)", text: $cardAccessNumberEntry)
          .keyboardType(.numberPad)
          .focused($isCardAccessNumberFieldFocused)
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
      TextField("Card Access Number (CAN)", text: $cardAccessNumberEntry)
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
  ///
  /// A demonstration seeds nothing. It reads no stored value at all, so
  /// a card this device really knows about is not put on a screen that
  /// is showing a test person.
  private func showStoredCardAccessNumber() {
    guard !isDemonstration else { return }
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

  /// Returns the transient PIN only to the card-reading operation.
  @MainActor
  private func enteredPin1() -> String? {
    guard isPin1EntryComplete else { return nil }
    isPin1FieldFocused = false
    return pin1Entry
  }

  /// Removes PIN1 from UI memory after every completed NFC operation.
  @MainActor
  private func clearPin1Entry() {
    pin1Entry = ""
    isPin1FieldFocused = false
  }

  /// Runs the first non-mutating connection and routes from live card state.
  private func connectIdentityCard() {
    guard isCardAccessNumberEntryComplete, !model.isConnecting else { return }
    if isDemonstration {
      demonstrationConnected = true
      isCardAccessNumberFieldFocused = false
      return
    }
    let entered = cardAccessNumberEntry
    activationScheme = nil
    activationNeeds = nil
    isCardAccessNumberFieldFocused = false
    Task {
      guard let result = await model.connect(cardAccessNumber: entered) else { return }
      guard entered == cardAccessNumberEntry else { return }
      switch result {
      case .activated:
        model.forgetPin1()
        if !model.saveCardAccessNumber(entered) {
          cardAccessNumberEntry = ""
          isCardAccessNumberFieldFocused = true
        }
      case .activationRequired(let scheme, let needs):
        model.forgetPin1()
        activationScheme = scheme
        activationNeeds = needs
        destination = .activation
      case .wrongCardAccessNumber:
        cardAccessNumberEntry = ""
        isCardAccessNumberFieldFocused = true
      case .failed:
        break
      }
    }
  }

  /// Activation succeeded on the card; only now is its CAN persistent.
  private func activationSucceeded() {
    activationScheme = nil
    activationNeeds = nil
    if !model.saveCardAccessNumber(cardAccessNumberEntry) {
      cardAccessNumberEntry = ""
      isCardAccessNumberFieldFocused = true
    }
  }

  /// Empties both fields once they have nothing left to describe.
  private func clearEntries() {
    cardAccessNumberEntry = ""
    pin1Entry = ""
    isCardAccessNumberFieldFocused = false
    isPin1FieldFocused = false
  }
}
