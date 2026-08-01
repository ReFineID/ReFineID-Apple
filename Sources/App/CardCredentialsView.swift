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
  @State private var isPin1Revealed = false
  @State private var showsForgetConfirmation = false
  @State private var registrationReset = false
  @State private var isRegistered = false
  @FocusState private var isPin1FieldFocused: Bool

  /// The PIN is valid for storage only inside the card's documented range.
  private var isPin1EntryComplete: Bool {
    pin1Entry.count >= Pin1.minimumDigitCount
      && pin1Entry.count <= Pin1.maximumDigitCount
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
      // A set identity replaces the whole setup: nothing about it is
      // left to configure, so nothing about configuring it is shown.
      if isRegistered {
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
      if model.hasForgettableState {
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
    }
    #if os(iOS)
      .sheet(isPresented: $isScanning) {
        scannerSheet
      }
    #endif
    .alert(
      isRegistered ? "Forget identity?" : "Forget card details?",
      isPresented: $showsForgetConfirmation
    ) {
      Button("Forget", role: .destructive) {
        model.forgetEverything()
        registrationReset.toggle()
        isRegistered = false
      }
    }
  }

  /// The finished state: one word, one mark.
  private var identitySection: some View {
    Section {
      LabeledContent("Identity") {
        Image(systemName: "checkmark")
          .foregroundStyle(.green)
          .accessibilityLabel("Set")
      }
      .accessibilityIdentifier("identityStatus")
    }
  }

  /// One operation, in its actual order: credentials and then minting.
  @ViewBuilder private var createIdentitySection: some View {
    Section("Set up Finnish ID card") {
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
          isRegistered: $isRegistered
        )
        .id(registrationReset)
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    #endif
  }

  /// The stored marker shown beside a credential that is already kept.
  private var storedMark: some View {
    Image(systemName: "checkmark")
      .foregroundStyle(.green)
      .accessibilityLabel("Stored")
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
          .accessibilityIdentifier("cardAccessNumberField")
          .onChange(of: cardAccessNumberEntry) { _, typed in
            cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
          }
        if model.contents.hasCardAccessNumber {
          storedMark
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

  /// PIN1 entry, editable for as long as there is no identity.
  ///
  /// A stored PIN is never read back, so the field stays empty and the
  /// mark beside it is what says one is kept. Typing replaces it.
  @ViewBuilder private var pin1Row: some View {
    HStack {
      Group {
        if isPin1Revealed {
          TextField("PIN1", text: $pin1Entry)
        } else {
          SecureField("PIN1", text: $pin1Entry)
        }
      }
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

      if model.contents.hasPin1 {
        storedMark
      }
      pin1VisibilityButton
    }
  }

  /// Standard transient visibility control for the unsaved PIN.
  private var pin1VisibilityButton: some View {
    Button {
      isPin1Revealed.toggle()
      isPin1FieldFocused = true
    } label: {
      Label(
        isPin1Revealed ? "Hide PIN1" : "Show PIN1",
        systemImage: isPin1Revealed ? "eye.slash" : "eye"
      )
      .labelStyle(.iconOnly)
    }
    .buttonStyle(.borderless)
    .disabled(pin1Entry.isEmpty)
    .accessibilityIdentifier("pin1Visibility")
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

  /// The destructive action, named for what it actually removes.
  ///
  /// Before an identity exists there is none to forget, and offering to
  /// forget one is a promise about state the device does not hold. What
  /// it does hold then is the two credentials, so that is what it says.
  private var forgetSection: some View {
    Section {
      Button(
        isRegistered ? "Forget identity" : "Forget card details",
        role: .destructive
      ) {
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

    cardAccessNumberEntry = ""
    pin1Entry = ""
    isPin1Revealed = false
    isPin1FieldFocused = false

    return model.prepareIdentity(
      cardAccessNumber: accessNumber,
      pin1: pin1)
  }
}
