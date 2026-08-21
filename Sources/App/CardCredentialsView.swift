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

  // MARK: Nested Types

  private enum CardConnectionPurpose: Sendable {
    case pinManagement
  }

  // MARK: Static Properties

  private static let sectionSpacing: CGFloat = 24

  /// Between a borrowed person and the control that drops them.
  private static let holderActionSpacing: CGFloat = 12

  /// The scanner button beside the printed digits.
  private enum Layout {
    static let canButtonSize = 44.0
    static let canButtonOuterPadding = -10.0
  }

  // MARK: Static Computed Properties

  /// The seal drawn beside document verification.
  ///
  /// A symbol added after the system running this build resolves to
  /// nothing and leaves the row without its mark, so the newer name is
  /// used only where it exists.
  private static var verificationSymbolName: String {
    #if os(iOS)
      UIImage(systemName: "checkmark.seal.text.page") != nil
        ? "checkmark.seal.text.page" : "checkmark.seal"
    #else
      "checkmark.seal.text.page"
    #endif
  }

  // MARK: SwiftUI Properties

  @StateObject private var model = CardCredentialsModel()
  @ObservedObject private var retryHealth = CredentialRetryHealth.shared
  #if os(iOS)
    @ObservedObject private var demoMode = DemoMode.shared
  #endif
  @State private var cardAccessNumberEntry = ""
  @State private var pin1Entry = ""
  @State private var isScanning = false
  @State private var scannerTorchEnabled = false
  @State private var showsForgetConfirmation = false
  @State private var registrationReset = false
  @State private var isRegistered = false
  @State private var activationScheme: ActivationScheme?
  @State private var activationNeeds: CardActivationNeeds?
  @State private var flowState = CardSetupStateMachine.initialState
  @FocusState private var isCardAccessNumberFieldFocused: Bool
  @FocusState private var isPin1FieldFocused: Bool

  #if REFINEID_LOCAL_CARD && os(iOS)
    /// The priming model lives here, above everything a hold hides.
    @StateObject private var primingModel = CardPrimingModel()
  #endif

  // MARK: Properties

  #if os(iOS)
    /// Live reader identities, when an iOS root provides them.
    private let readerModel: ReaderIdentityModeModel?

    #if REFINEID_REMOTE_CARD
      /// The requester's view of the selected remote card.
      private let remoteModel: RemoteCardModel

      /// Opens the remote reader connections owned by the root.
      private let openRemoteReader: () -> Void
    #endif

    /// The holder names read from the live reader tokens.
    @State private var readerHolders: [String] = []

    /// Whether the document verification screen is pushed.
    @State private var showsDocumentVerify = false
  #endif

  // MARK: Computed Properties

  /// The complete visible CAN handed to signing and PIN management.
  ///
  /// These routes can establish and verify their own card session, so they
  /// become available at six digits without requiring an earlier NFC read.
  internal var managementCardAccessNumber: String? {
    isCardAccessNumberEntryComplete ? cardAccessNumberEntry : nil
  }

  /// The PIN is valid for storage only inside the card's documented range.
  private var isPin1EntryComplete: Bool {
    pin1Entry.count >= Pin1.minimumDigitCount
      && pin1Entry.count <= Pin1.maximumDigitCount
  }

  /// The point at which operations using the printed card number can be
  /// offered.
  ///
  /// Until all six digits exist, PIN1 has no card to belong to.
  private var isCardAccessNumberEntryComplete: Bool {
    cardAccessNumberEntry.count == CardAccessNumber.digitCount
  }

  /// CAN receives initial focus as the first input of an unconfigured card.
  private var shouldFocusCardAccessNumber: Bool {
    !hasIdentity
      && offersNearField
      && !isHolding
      && !isCardAccessNumberEntryComplete
  }

  /// Disclosure follows a validated connection, never digit count alone.
  private var hasConfiguredCard: Bool {
    #if os(iOS)
      if isDemonstration {
        return demoMode.hasValidatedConnection
      }
    #endif
    return model.contents.hasCardAccessNumber
  }

  /// Whether this launch routes every card and device effect to a virtual card.
  ///
  /// Every branch below that reads it stays inside the process-scoped virtual
  /// environment and does not touch physical I/O, Keychain, or token state.
  private var isDemonstration: Bool {
    #if os(iOS)
      return demoMode.isActive
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
        return demoMode.hasIdentity ? demoMode.holderName : nil
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
    #if REFINEID_LOCAL_CARD && os(iOS)
      return model.isConnecting || primingModel.isRunning || demoMode.isHolding
    #else
      return false
    #endif
  }

  /// Whether this device has an antenna to set an identity with.
  ///
  /// An iPad has none, and runs the same binary as an iPhone. Offering
  /// it a card setup it can never finish -- two fields to fill and a
  /// button that only ever stays grey -- describes the app as broken
  /// rather than the device as different. A demonstration fakes the
  /// antenna, never the device class.
  private var offersNearField: Bool {
    #if REFINEID_LOCAL_CARD && os(iOS)
      return primingModel.allowsNearField
        || (isDemonstration && DemoMode.offersNearField)
    #elseif os(iOS)
      // A build without the local card path has no way to reach a card of
      // its own: an iPad has no antenna and no reader to attach one to.
      return false
    #else
      return true
    #endif
  }

  /// Whether a connected reader's card still requires activation.
  private var readerActivationRequired: Bool {
    #if os(iOS)
      return readerModel?.hasActivationRequiredCard ?? false
    #else
      return false
    #endif
  }

  /// Whether an activated reader-backed identity is live.
  private var hasReaderIdentity: Bool {
    #if os(iOS)
      return (readerModel?.isActive ?? false) && !readerActivationRequired
    #else
      return false
    #endif
  }

  /// Both credentials must be usable before minting starts.
  ///
  /// A field left empty falls back to what is stored; a field with
  /// something in it has to be complete, because a half-typed
  /// replacement is a replacement the holder is still writing.
  ///
  /// A demonstration validates the transient PIN against its virtual card and
  /// never falls back to credentials stored for a physical identity.
  private var canPrepareIdentity: Bool {
    #if os(iOS)
      if isDemonstration {
        return demoMode.hasValidatedConnection && isPin1EntryComplete
      }
    #endif
    return model.contents.hasCardAccessNumber && isPin1EntryComplete
  }

  #if os(iOS)
    /// The document routes, active once a card path exists.
    ///
    /// Each route opens its own screen, so the rows read as navigation
    /// rather than as immediate actions.
    /// Whether a qualified signature can start right now.
    private var signingAvailable: Bool {
      hasReaderIdentity || isCardAccessNumberEntryComplete
    }

    private var signingSection: some View {
      // Verification asks for no card and no identity, so it leads.
      Section {
        Button {
          showsDocumentVerify = true
        } label: {
          navigationRow(
            String(
              localized: "verify.title",
              defaultValue: "Verify",
              table: "DocumentSigning")
          ) {
            Image(systemName: Self.verificationSymbolName)
              .foregroundStyle(Color.accentColor)
          }
        }
        .tint(.primary)
        .accessibilityIdentifier("verifyDocuments")
        // Signing reaches the card for a qualified signature, so the route
        // belongs to a device that can reach one.
        if offersNearField || hasReaderIdentity {
          Button {
            synchronizeIdentityState()
            transition(.openDocumentSigning)
          } label: {
            navigationRow(
              String(
                localized: "signing.title",
                defaultValue: "Sign",
                table: "DocumentSigning")
            ) {
              Image(systemName: "signature")
                .foregroundStyle(
                  signingAvailable
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.secondary))
            }
          }
          .tint(.primary)
          .accessibilityIdentifier("signDocuments")
          .disabled(!signingAvailable)
        }
      } header: {
        compactSectionHeader(
          verbatim: String(
            localized: "signing.document",
            defaultValue: "Document",
            table: "DocumentSigning"))
      }
    }

    /// Whether the credential management route can be taken right now.
    private var managementAvailable: Bool {
      (isCardAccessNumberEntryComplete || hasReaderIdentity)
        && !model.isConnecting
    }

    #if REFINEID_REMOTE_CARD
      /// Whether the remote card route can be taken right now.
      ///
      /// A card holder serves a remote card from a primed identity or
      /// a live reader identity; a requesting device consumes one and
      /// needs none.
      private var remoteCardAvailable: Bool {
        !offersNearField || hasIdentity || hasReaderIdentity
      }
    #endif

    /// The card's credential management route.
    private var cardSection: some View {
      Section {
        #if REFINEID_REMOTE_CARD
          // A device that reaches a card of its own can also serve one, and
          // this route is how it offers that. A device without one only ever
          // consumes a remote card, which the identity row already connects.
          if offersNearField {
            Button {
              openRemoteReader()
            } label: {
              navigationRow(String(localized: "Remote Card")) {
                Image(
                  systemName: remoteCardAvailable
                    ? "key.radiowaves.forward"
                    : "key.radiowaves.forward.slash"
                )
                .foregroundStyle(
                  remoteCardAvailable
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.secondary)
                )
                .accessibilityHidden(true)
              }
            }
            .tint(.primary)
            .accessibilityIdentifier("remoteCard")
            .disabled(!remoteCardAvailable)
          }
        #endif
        // Changing a code writes to the card itself, so the route belongs to
        // a device that can reach one. Offering it where it can never open
        // describes the app as broken rather than the device as different.
        if offersNearField || hasReaderIdentity {
          Button {
            openCardManagement()
          } label: {
            navigationRow(
              String(localized: "Personal Identification Numbers (PINs)")
            ) {
              // A closed route greys the keys; health color returns
              // with availability.
              CredentialRetryHealthKey(
                level: retryHealth.level,
                systemName: "key.2.on.ring",
                routeAvailable: managementAvailable)
            }
          }
          .tint(.primary)
          .accessibilityIdentifier("manageCard")
          .disabled(!managementAvailable)
        }
      } header: {
        compactSectionHeader("Card")
      }
    }

    /// Who the connected reader's card says they are, one row per card.
    ///
    /// The reader message stands in for a card whose name cannot be
    /// read: a live token with no readable name is still a card present.
    private var readerIdentitySection: some View {
      Section {
        if readerHolders.isEmpty {
          Text(readerMessage)
            .foregroundStyle(.secondary)
        } else {
          ForEach(readerHolders, id: \.self) { holder in
            LabeledContent {
              Text(holder)
                .textSelection(.enabled)
                .accessibilityIdentifier("readerCardHolder")
            } label: {
              PersonRowLabel(configured: true)
            }
          }
        }
      } header: {
        compactSectionHeader("Identity")
      }
    }

    /// Distinguishes one usable reader from several without exposing
    /// card data.
    private var readerMessage: String {
      if (readerModel?.liveReaderTokenCount ?? 0) == 1 {
        String(localized: "USB-C reader connected with ID card.")
      } else {
        String(localized: "USB-C readers connected with ID cards.")
      }
    }

    /// Changes whenever the identities rendered by the reader rows change.
    private var readerHolderReadKey: [String] {
      readerModel?.holderReadKey ?? []
    }
  #endif

  /// SwiftUI navigation is a projection of the formal flow state.
  ///
  /// A pop is fed back as an event so origin restoration is modeled as
  /// well.
  private var flowDestination: Binding<CardSetupStateMachine.Destination?> {
    Binding(
      get: { flowState.destination },
      set: { destination in
        guard destination == nil, flowState.destination != nil else { return }
        transition(.destinationDismissed)
      }
    )
  }

  // MARK: Content Properties

  internal var body: some View {
    #if os(iOS)
      if readerActivationRequired {
        // A factory-fresh reader card opens activation in place of setup.
        CardManagementView(readerCardIsPresent: true, activationRequired: true)
          .navigationTitle("ReFineID")
          .navigationBarTitleDisplayMode(.large)
      } else {
        credentialsForm
      }
    #else
      credentialsForm
    #endif
  }

  /// The screen's identity area: exactly one of the hold blank, the
  /// live reader identity, the reader-only notice, the set identity,
  /// or the setup form.
  @ViewBuilder private var identityArea: some View {
    // While the card is against the phone, Apple's panel is the
    // screen and everything under it is furniture behind frosted
    // glass. Clearing it leaves the app's name, which is all a
    // dimmed backdrop can usefully say.
    if isHolding {
      EmptyView()
    } else if hasReaderIdentity {
      readerIdentitySection
    } else if !offersNearField {
      // No antenna: a local or remote reader is the way in. There is
      // nothing to store first -- a card in a contact reader needs no
      // access number.
      remoteReaderSection
    } else if let identityHolder {
      // A set identity replaces the whole setup: nothing about it is
      // left to configure, so nothing about configuring it is shown.
      CardIdentitySection(holder: identityHolder) {
        showsForgetConfirmation = true
      }
    } else {
      createIdentitySection
    }
  }

  /// The form and its navigation chrome, typed separately from the
  /// event handlers so each half stays checkable on its own.
  private var navigationChrome: some View {
    // Ordered by how little the holder needs: verification asks for
    // nothing and leads, the card routes follow, and the identity --
    // the only part with any setup -- closes the page.
    Form {
      #if os(iOS)
        if !isHolding {
          signingSection
          // A heading over nothing is a heading about nothing: the section
          // appears only where at least one of its routes can open.
          if offersNearField || hasReaderIdentity {
            cardSection
          }
        }
      #endif
      #if !os(iOS)
        if !isHolding {
          managementSection
        }
      #endif
      identityArea
      // A message about the previous attempt has nothing to say
      // while a new scan is already running behind the panel.
      if let failure = model.failure, !isHolding {
        Section {
          CredentialOutcomeText(message: failure, tone: .failure)
        }
      }
    }
    #if os(iOS)
      .listSections(spacing: Self.sectionSpacing)
      .navigationTitle("ReFineID")
      .navigationBarTitleDisplayMode(.large)
      .navigationDestination(
        isPresented: Binding(
          get: { flowDestination.wrappedValue != nil },
          set: { presented in
            if !presented { flowDestination.wrappedValue = nil }
          }
        )
      ) {
        if let destination = flowDestination.wrappedValue {
          destinationView(destination)
        }
      }
      .navigationDestination(isPresented: $showsDocumentVerify) {
        VerifyDocumentView()
      }
    #endif
  }

  private var credentialsForm: some View {
    navigationChrome
      // Pinned under every product control: what this run is, when it is
      // anything but the shipped product doing its job.
      .safeAreaInset(edge: .bottom) {
        #if os(iOS)
          let includesFooter = !demoMode.isEditorPresented
        #else
          let includesFooter = true
        #endif
        if includesFooter {
          let hidesFooter =
            isCardAccessNumberFieldFocused || isPin1FieldFocused
          CardSetupFooter(isDemonstration: isDemonstration)
            // Keep the inset structurally stable while the keyboard is present.
            // Removing it rebuilds Form cells and strands UIKit's keyboard with
            // no first responder. An invisible footer is also absent to touch and
            // accessibility users, without changing the input hierarchy.
            .opacity(hidesFooter ? 0 : 1)
            .allowsHitTesting(!hidesFooter)
            .accessibilityHidden(hidesFooter)
        }
      }
      .onAppear {
        model.refresh()
        refreshRegistration()
        showStoredCardAccessNumber()
        synchronizeIdentityState()
      }
      #if os(iOS)
        .task(id: readerHolderReadKey) {
          readerHolders = await readerModel?.holderNames() ?? []
        }
      #endif
      .onValueChange(of: hasIdentity) { registered in
        // A set identity ends the fields' job; nothing they held is worth
        // keeping in memory once the setup they belonged to is over.
        if registered {
          // Registration can arrive from the visible Virtual ID Card editor as
          // well as from a real card operation. Keep the same stored-CAN input
          // invariant in both cases so the management key is immediately usable.
          showStoredCardAccessNumber()
          finishBrowserRegistration(succeeded: true)
          clearPin1Entry()
        } else {
          synchronizeIdentityState()
        }
      }
      .onValueChange(of: model.contents) { _ in
        // A hold that stored the number and then broke leaves the field
        // as it was. Seeding again here puts the stored number back in
        // front of the holder, which is where a wrong one gets noticed.
        showStoredCardAccessNumber()
      }
      #if os(iOS)
        .onReceive(
          NotificationCenter.default.publisher(
            for: .virtualIDCardEditorDidDismiss)
        ) { _ in
          // The floating editor owns focus while it is open. Reset the bindings
          // before returning focus to the CAN field on the next event turn.
          isCardAccessNumberFieldFocused = false
          isPin1FieldFocused = false
          DispatchQueue.main.async {
            guard shouldFocusCardAccessNumber else { return }
            isCardAccessNumberFieldFocused = true
          }
        }
      #endif
      .onValueChange(of: isCardAccessNumberEntryComplete) { complete in
        // A PIN entered for one complete CAN must not survive while that
        // CAN is erased or replaced. It reappears only after the new card
        // number is complete and the holder enters its PIN deliberately.
        if !complete {
          pin1Entry = ""
          isPin1FieldFocused = false
          #if os(iOS)
            if isDemonstration {
              demoMode.forgetIdentity()
            }
          #endif
        }
      }
      .onValueChange(of: cardAccessNumberEntry) { entered in
        model.invalidateCardStatus()
        activationScheme = nil
        activationNeeds = nil
        if !entered.isEmpty {
          model.clearFailure()
        }
        guard entered.isEmpty,
          !isDemonstration,
          model.contents.hasCardAccessNumber
        else { return }
        Task { await model.forgetEverything() }
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: CardCredentialStore.cardAccessNumberDidInvalidate)
      ) { _ in
        model.refresh()
        cardAccessNumberEntry = ""
        clearPin1Entry()
        activationScheme = nil
        activationNeeds = nil
        model.invalidateCardStatus()
        isCardAccessNumberFieldFocused = true
      }
      #if REFINEID_LOCAL_CARD && os(iOS)
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
              demoMode.forgetIdentity()
              clearEntries()
              return
            }
          #endif
          Task {
            await model.forgetEverything()
            registrationReset.toggle()
            isRegistered = false
            synchronizeIdentityState()
            clearEntries()
          }
        }
      }
  }

  #if os(iOS) && REFINEID_REMOTE_CARD
    /// The identity surface of a device with no antenna and no reader:
    /// the person is reached through a remote reader.
    private var remoteReaderSection: some View {
      Section {
        LabeledContent {
          switch remoteModel.phase {
          case .connecting:
            ProgressView()
          case .identity(let holder):
            HStack(spacing: Self.holderActionSpacing) {
              Text(holder)
                .textSelection(.enabled)
                .accessibilityIdentifier("remoteCardHolder")
              Button {
                remoteModel.forget()
              } label: {
                Image(systemName: "minus.circle.fill")
                  .foregroundStyle(.red)
              }
              .buttonStyle(.borderless)
              .accessibilityIdentifier("forgetRemoteIdentity")
              .accessibilityLabel(String(localized: "Forget identity"))
            }
          case .idle, .failed:
            Button(String(localized: "Connect Remote Reader")) {
              // A pairing already held is asked, whatever antenna this device
              // has. Requiring one of its own sent every device this button
              // is for to a fresh code while a working pairing sat unused,
              // so the certificate the tap was for was never asked for. A
              // pairing the peer no longer honours still ends at the code,
              // by way of ``needsFreshPairing``.
              if remoteModel.hasPair {
                remoteModel.connect()
              } else {
                openRemoteReader()
              }
            }
            .accessibilityIdentifier("connectRemoteReader")
          }
        } label: {
          PersonRowLabel(configured: remoteModel.holder != nil)
        }
        if remoteModel.phase == .failed {
          Text(remoteModel.failureText ?? String(localized: "The remote card could not be read."))
            .foregroundStyle(.secondary)
        }
      } header: {
        compactSectionHeader("Identity")
      }
      // A pairing the peer no longer honours has just been discarded, so
      // the code that makes a new one comes up without asking for the same
      // tap twice.
      .onValueChange(of: remoteModel.needsFreshPairing) { needsFresh in
        if needsFresh {
          remoteModel.acknowledgeFreshPairing()
          openRemoteReader()
        }
      }
    }
  #else
    /// Unreachable on macOS, where ``offersNearField`` is always true,
    /// and absent with the remote card: a device that cannot consume a
    /// remote reader offers no surface for one.
    private var remoteReaderSection: some View {
      EmptyView()
    }
  #endif

  #if os(macOS)
    /// Unreachable on macOS: ``hasReaderIdentity`` is always false there.
    private var readerIdentitySection: some View {
      EmptyView()
    }
  #endif

  /// One operation, in its actual order: credentials and then minting.
  @ViewBuilder private var createIdentitySection: some View {
    Section {
      cardAccessNumberRow
    } header: {
      compactSectionHeader("Connect Identity Card")
    }
    Section {
      pin1Row
    } header: {
      compactSectionHeader("Browser authentication")
    }
    if hasConfiguredCard {
      #if REFINEID_LOCAL_CARD && os(iOS)
        // Its own section and its own visual weight: the credential rows
        // collect input, this is the screen's one primary action.
        //
        // The section registers the card through the system's card slot,
        // which arrived in iOS 26. An older system reaches this only on a
        // device whose antenna it cannot open, so the section is absent
        // rather than present and unusable.
        if #available(iOS 26.0, *) {
          Section {
            CardRegistrationSections(
              canPrepareCredentials: canPrepareIdentity,
              isDemonstration: isDemonstration,
              enteredPin1: enteredPin1,
              cardAccessNumber: registrationCardAccessNumber,
              storeCardAccessNumber: storeProvenCardAccessNumber,
              storeVerifiedPin1: storeVerifiedPin1,
              clearPin1Entry: clearPin1Entry,
              onRegistrationStarted: {
                transition(.startConfiguredBrowserRegistration)
              },
              onRegistrationFinished: { succeeded in
                finishBrowserRegistration(succeeded: succeeded)
              },
              isRegistered: $isRegistered,
              model: primingModel
            )
            .id(registrationReset)
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        if let failure = primingModel.failure {
          Section {
            CredentialOutcomeText(message: failure, tone: .failure)
              .accessibilityIdentifier("primeFailureMessage")
          }
        }
      #endif
    } else {
      Section {
        Button {
          connectIdentityCard()
        } label: {
          BrowserAuthenticationEnableLabel()
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          !isCardAccessNumberEntryComplete
            || !isPin1EntryComplete
            || model.isConnecting
        )
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
        TextField(
          "Card Access Number (CAN)",
          text: $cardAccessNumberEntry
        )
        .font(.body)
        .keyboardType(.numberPad)
        .textContentType(nil)
        .focused($isCardAccessNumberFieldFocused)
        .accessibilityIdentifier("cardAccessNumberField")
        .onAppear {
          // This row is the entire first-use interaction. Request focus only
          // after the actual field has joined the hierarchy, on the next
          // event turn, so the request cannot create a keyboard without a
          // surviving first responder.
          DispatchQueue.main.async {
            guard shouldFocusCardAccessNumber else { return }
            isCardAccessNumberFieldFocused = true
          }
        }
        .onValueChange(of: cardAccessNumberEntry) { typed in
          cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
        }
        #if REFINEID_LOCAL_CARD && os(iOS)
          if CardAccessNumberScanner.isAvailable {
            Button {
              scannerTorchEnabled = false
              isScanning = true
            } label: {
              Label("Scan", systemImage: "camera")
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .frame(width: Layout.canButtonSize, height: Layout.canButtonSize)
            .contentShape(Rectangle())
            .padding(Layout.canButtonOuterPadding)
          }
        #endif
      }
    #else
      TextField(
        "Card Access Number (CAN)",
        text: $cardAccessNumberEntry
      )
      .font(.body)
      .accessibilityIdentifier("cardAccessNumberField")
      .onValueChange(of: cardAccessNumberEntry) { typed in
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
    CredentialSecretField(
      name: String(localized: "Basic Code (PIN 1)"),
      text: $pin1Entry,
      revealIdentifier: "pin1FieldReveal"
    ) {
      SecureField("Basic Code (PIN 1)", text: $pin1Entry)
        .font(.body)
        #if os(iOS)
          .keyboardType(.numberPad)
          .textInputAutocapitalization(.never)
        #endif
        .autocorrectionDisabled()
        .focused($isPin1FieldFocused)
        .accessibilityIdentifier("pin1Field")
        .onValueChange(of: pin1Entry) { typed in
          pin1Entry = LimitedDigits.pin1(typed)
        }
    }
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
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

  // MARK: Lifecycle

  #if os(iOS)
    #if REFINEID_REMOTE_CARD
      internal init(
        readerModel: ReaderIdentityModeModel?,
        remoteModel: RemoteCardModel,
        openRemoteReader: @escaping () -> Void
      ) {
        self.readerModel = readerModel
        self.remoteModel = remoteModel
        self.openRemoteReader = openRemoteReader
      }
    #else
      internal init(readerModel: ReaderIdentityModeModel?) {
        self.readerModel = readerModel
      }
    #endif
  #endif

  // MARK: Content Methods

  private func navigationRow(
    _ title: String,
    @ViewBuilder icon: () -> some View
  ) -> some View {
    HStack {
      icon()
        .frame(width: PersonRowLabel.iconWidth)
        .accessibilityHidden(true)
      Text(title)
      Spacer()
      Image(systemName: "chevron.forward")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
  }

  private func compactSectionHeader(
    _ title: LocalizedStringKey
  ) -> some View {
    Text(title)
      .frame(maxWidth: .infinity, alignment: .leading)
      .listRowInsets(EdgeInsets())
  }

  private func compactSectionHeader(verbatim title: String) -> some View {
    Text(title)
      .frame(maxWidth: .infinity, alignment: .leading)
      .listRowInsets(EdgeInsets())
  }

  #if os(iOS)
    /// The pushed screen for one flow destination.
    ///
    /// A live reader identity signs and manages over its own card
    /// session; the wireless routes carry the entered CAN instead.
    @ViewBuilder
    private func destinationView(
      _ destination: CardSetupStateMachine.Destination
    ) -> some View {
      switch destination {
      case .activation:
        #if DEBUG
          // A result builder accepts a declaration, not a discard statement.
          // swiftlint:disable:next redundant_discardable_let
          let _ = DebugConsole.emit("navigation-destination: activation")
        #endif
        if let activationScheme, let activationNeeds {
          CardManagementView(
            activationRequired: true,
            cardAccessNumber: cardAccessNumberEntry,
            activationScheme: activationScheme,
            activationNeeds: activationNeeds,
            onActivationSucceeded: activationSucceeded
          )
          .id(CardSetupStateMachine.Destination.activation)
        }
      case .pinManagement:
        #if DEBUG
          // A result builder accepts a declaration, not a discard statement.
          // swiftlint:disable:next redundant_discardable_let
          let _ = DebugConsole.emit("navigation-destination: PIN management")
        #endif
        if hasReaderIdentity {
          CardManagementView(readerCardIsPresent: true)
            .id(CardSetupStateMachine.Destination.pinManagement)
        } else {
          CardManagementView(
            cardAccessNumber: managementCardAccessNumber
          )
          .id(CardSetupStateMachine.Destination.pinManagement)
        }
      case .signDocuments:
        DocumentSigningView(
          transport: hasReaderIdentity ? .reader : .nearField,
          cardAccessNumber: hasReaderIdentity ? nil : managementCardAccessNumber
        )
        .id(CardSetupStateMachine.Destination.signDocuments)
      }
    }
  #endif

  // MARK: Functions

  /// Puts a stored card access number back in its field.
  ///
  /// The number is printed on the card face and is the holder's to see,
  /// so a stored one is shown rather than asserted by a mark beside an
  /// empty box. Seeing the digits is also the only way to notice that
  /// the stored ones are wrong, which is the usual reason a setup breaks
  /// half way.
  ///
  /// A demonstration displays only its virtual device state, so a CAN stored
  /// for a physical identity cannot appear beside a fictional holder.
  private func showStoredCardAccessNumber() {
    #if os(iOS)
      if isDemonstration {
        guard cardAccessNumberEntry.isEmpty else { return }
        cardAccessNumberEntry = demoMode.displayedCardAccessNumber ?? ""
        return
      }
    #endif
    guard cardAccessNumberEntry.isEmpty, let stored = model.storedCardAccessNumber else {
      return
    }
    cardAccessNumberEntry = stored
  }

  /// Reads the persistent registration state, on the platform that has it.
  private func refreshRegistration() {
    #if REFINEID_LOCAL_CARD && os(iOS)
      // A system without the card slot has no registration to read, so
      // the answer is the same one it gives before the first hold.
      guard #available(iOS 26.0, *) else { return }
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

  /// One side-effect-free NFC snapshot decides activation, recovery, and the
  /// healthy path before PIN management opens.
  ///
  /// Browser setup does not come through here: it proves the access number
  /// inside the one hold that also reads and registers the identity, so it
  /// never spends a second field on a question it can answer in the first.
  private func classifyIdentityCard(for purpose: CardConnectionPurpose) {
    guard isCardAccessNumberEntryComplete, !model.isConnecting else { return }
    let started: Bool
    switch purpose {
    case .pinManagement:
      started = transition(.startManagementClassification)
    }
    guard started else { return }
    let entered = cardAccessNumberEntry
    activationScheme = nil
    activationNeeds = nil
    isCardAccessNumberFieldFocused = false
    Task {
      guard let result = await model.connect(cardAccessNumber: entered) else {
        transition(.classificationFailed)
        return
      }
      guard entered == cardAccessNumberEntry else {
        model.invalidateCardStatus()
        transition(.classificationFailed)
        return
      }
      switch result {
      case .activated:
        if !isDemonstration, !model.saveCardAccessNumber(entered) {
          cardAccessNumberEntry = ""
          clearPin1Entry()
          isCardAccessNumberFieldFocused = true
          transition(.classificationFailed)
          return
        }
        if retryHealth.recovery != nil {
          clearPin1Entry()
          transition(.classificationRecoveryRequired)
          return
        }
        switch purpose {
        case .pinManagement:
          clearPin1Entry()
          transition(.classificationActivated)
        }
      case .activationRequired(let scheme, let needs):
        if !isDemonstration {
          model.forgetPin1()
        }
        clearPin1Entry()
        activationScheme = scheme
        activationNeeds = needs
        transition(.classificationActivationRequired)
      case .wrongCardAccessNumber:
        // A primed identity whose stored CAN the card refuses is
        // facing a different card: every authority is removed and
        // setup starts over from the access number.
        if !isDemonstration, hasIdentity {
          await model.forgetEverythingAfterCardMismatch()
        }
        cardAccessNumberEntry = ""
        isCardAccessNumberFieldFocused = true
        clearPin1Entry()
        transition(.classificationWrongCardAccessNumber)
      case .failed:
        clearPin1Entry()
        transition(.classificationFailed)
      }
    }
  }

  /// Activation succeeded on the card; only now is its CAN persistent.
  private func activationSucceeded() {
    activationScheme = nil
    activationNeeds = nil
    if isDemonstration {
      showStoredCardAccessNumber()
      transition(.activationSucceeded)
      return
    }
    if !model.saveCardAccessNumber(cardAccessNumberEntry) {
      cardAccessNumberEntry = ""
      isCardAccessNumberFieldFocused = true
    }
    transition(.activationSucceeded)
  }

  /// Persistent identity is an input event, never an alternate navigation
  /// branch outside the reducer.
  private func synchronizeIdentityState() {
    if hasIdentity, flowState == .home {
      transition(.identityLoaded)
    } else if !hasIdentity, flowState == .identityHome {
      transition(.identityForgotten)
    }
  }

  /// Commits verified PIN 1 at the device boundary.
  ///
  /// A Virtual ID Card already models the same successful persistence and
  /// token-publication effects inside its simulated authenticate operation.
  /// It must never write demonstration credentials into the real Keychain.
  private func storeVerifiedPin1(_ pin1: String) -> Bool {
    #if os(iOS)
      if isDemonstration {
        return demoMode.hasIdentity
      }
    #endif
    return model.savePin1(pin1)
  }

  /// Completes registration from the operation result instead of waiting for
  /// SwiftUI to observe a separate identity mutation.
  ///
  /// The observation may run before or after the callback, so success is
  /// deliberately idempotent.
  private func finishBrowserRegistration(succeeded: Bool) {
    if flowState == .registeringBrowser {
      transition(succeeded ? .registrationSucceeded : .registrationFailed)
    } else if succeeded {
      synchronizeIdentityState()
    }
  }

  @discardableResult
  private func transition(_ event: CardSetupStateMachine.Event) -> Bool {
    switch CardSetupStateMachine.reduce(state: flowState, event: event) {
    case .transitioned(let target):
      flowState = target
      return true
    case .rejected:
      assertionFailure(
        "Rejected card-setup transition: \(flowState.rawValue) + \(event.rawValue)")
      return false
    }
  }

  /// The access number a registration hold should prove.
  ///
  /// The entered digits when the holder is setting the card up, and the
  /// stored ones when they are registering a card this device already
  /// knows.
  @MainActor
  private func registrationCardAccessNumber() -> String? {
    if isCardAccessNumberEntryComplete { return cardAccessNumberEntry }
    return CardCredentialStore.displayedCardAccessNumber()
  }

  /// Commits the access number at the device boundary, once proved.
  ///
  /// A demonstration models the same persistence without writing a real
  /// card's number into the Keychain.
  private func storeProvenCardAccessNumber(_ digits: String) -> Bool {
    #if os(iOS)
      if isDemonstration { return demoMode.hasValidatedConnection }
    #endif
    return model.saveCardAccessNumber(digits)
  }

  /// Sets the identity up in one hold.
  ///
  /// PACE proves the access number, the public certificate is read behind
  /// it, and the identity is registered -- all while the card is against
  /// the phone once. Neither credential is stored until that succeeded.
  ///
  /// The card is asked for nothing this setup will not use. Whether it
  /// accepts PIN1 is true of the card at the moment it signs, not of this
  /// moment, so the signing path reads its counter and verifies there; a
  /// PIN that turns out to be wrong discards the identity then.
  private func connectIdentityCard() {
    guard let pin1 = enteredPin1(), isCardAccessNumberEntryComplete else { return }
    guard transition(.startBrowserClassification) else { return }
    let entered = cardAccessNumberEntry
    activationScheme = nil
    activationNeeds = nil
    isCardAccessNumberFieldFocused = false
    model.clearFailure()
    model.invalidateCardStatus()
    Task { @MainActor in
      #if REFINEID_LOCAL_CARD && os(iOS)
        if #available(iOS 26.0, *) {
          let succeeded = await CardRegistrationSections.registerIdentity(
            cardAccessNumber: entered,
            pin1: pin1,
            model: primingModel,
            commit: IdentityCommitments(
              storeCardAccessNumber: storeProvenCardAccessNumber,
              storeVerifiedPin1: storeVerifiedPin1,
              clearPin1Entry: clearPin1Entry,
              markRegistered: { isRegistered = true }))
          finishIdentitySetup(succeeded: succeeded)
          return
        }
      #endif
      transition(.classificationFailed)
    }
  }

  /// Routes the one hold's outcome, reading what the card said.
  @MainActor
  private func finishIdentitySetup(succeeded: Bool) {
    #if REFINEID_LOCAL_CARD && os(iOS)
      guard #available(iOS 26.0, *) else { return }
      retryHealth.update(primingModel.credentialReport)
      guard !succeeded else {
        // The counters this hold read decide where the holder goes next.
        // An identity whose card is one wrong entry from blocking is worth
        // having, but the code needs restoring before it can sign, so the
        // route to that comes first.
        if retryHealth.recovery != nil {
          clearPin1Entry()
          transition(.classificationRecoveryRequired)
          return
        }
        transition(.classificationActivated)
        finishBrowserRegistration(succeeded: true)
        return
      }
      switch primingModel.refusal {
      case .wrongCardAccessNumber:
        Task { @MainActor in
          // A stored identity whose access number this card refuses is
          // facing a different card: every authority is removed and setup
          // starts over from the access number.
          if !isDemonstration, hasIdentity {
            await model.forgetEverythingAfterCardMismatch()
          }
          cardAccessNumberEntry = ""
          isCardAccessNumberFieldFocused = true
          clearPin1Entry()
          transition(.classificationWrongCardAccessNumber)
        }
      case .activationRequired(let scheme, let needs):
        clearPin1Entry()
        activationScheme = scheme
        activationNeeds = needs
        transition(.classificationActivationRequired)
      case nil:
        clearPin1Entry()
        transition(.classificationFailed)
      }
    #endif
  }

  /// A slashed key performs the prerequisite read; a verified key opens the
  /// route selected by that card state without repeating NFC work.
  ///
  /// A live reader identity opens management directly: its card is
  /// already present.
  private func openCardManagement() {
    if hasReaderIdentity {
      synchronizeIdentityState()
      transition(.openVerifiedManagement)
      return
    }
    guard isCardAccessNumberEntryComplete, !model.isConnecting else { return }
    synchronizeIdentityState()
    if let activationNeeds, activationNeeds.any {
      transition(.openKnownActivation)
    } else if model.hasVerifiedCardStatus {
      transition(.openVerifiedManagement)
    } else {
      classifyIdentityCard(for: .pinManagement)
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
