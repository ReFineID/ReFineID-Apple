import CardCore
import SwiftUI

/// Setting the card up: the access number, PIN1, and the hold that
/// registers the card for Safari.
///
/// This is the screen that matters, so it is the one the app opens on.
/// Technical state lives behind the Diagnostics row.
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

  @State private var model = CardCredentialsModel()
  @State private var cardAccessNumberEntry = ""
  @State private var pin1Entry = ""
  @State private var isScanning = false
  @State private var scannerTorchEnabled = false
  @State private var isPin1Revealed = false
  @State private var showsForgetConfirmation = false
  @State private var registrationReset = false
  @FocusState private var isPin1FieldFocused: Bool

  /// The PIN is valid for storage only inside the card's documented range.
  private var isPin1EntryComplete: Bool {
    pin1Entry.count >= Pin1.minimumDigitCount
      && pin1Entry.count <= Pin1.maximumDigitCount
  }

  /// Both credentials must be stored or complete before minting starts.
  private var canPrepareIdentity: Bool {
    (model.contents.hasCardAccessNumber
      || cardAccessNumberEntry.count == CardAccessNumber.digitCount)
      && (model.contents.hasPin1 || isPin1EntryComplete)
  }

  internal var body: some View {
    Form {
      createIdentitySection
      if let failure = model.failure {
        Section {
          Text(failure)
            .foregroundStyle(.red)
        }
      }
      diagnosticsSection
      forgetSection
    }
    #if os(iOS)
      .listSectionSpacing(Self.sectionSpacing)
      .navigationTitle("ReFineID")
      .navigationBarTitleDisplayMode(.large)
    #endif
    .onAppear { model.refresh() }
    #if os(iOS)
      .sheet(isPresented: $isScanning) {
        scannerSheet
      }
    #endif
    .alert(
      "Forget this card and identity?",
      isPresented: $showsForgetConfirmation
    ) {
      Button("Forget", role: .destructive) {
        model.forgetEverything()
        registrationReset.toggle()
      }
    }
  }

  /// One operation, in its actual order: credentials and then minting.
  private var createIdentitySection: some View {
    Section("Set up Finnish ID card") {
      cardAccessNumberRow
      pin1Row
      #if os(iOS)
        CardRegistrationSections(
          canPrepareCredentials: canPrepareIdentity,
          prepareCredentials: prepareIdentity
        )
        .id(registrationReset)
      #endif
    }
  }

  /// The CAN entry, or a compact indication that it is already stored.
  @ViewBuilder private var cardAccessNumberRow: some View {
    if model.contents.hasCardAccessNumber {
      LabeledContent("Card Access Number (CAN)") {
        Image(systemName: "checkmark")
          .foregroundStyle(.green)
          .accessibilityLabel("Stored")
      }
      .accessibilityIdentifier("cardAccessNumberStatus")
    } else {
      cardAccessNumberField
    }
  }

  /// PIN1 entry, or a compact indication that it is already stored.
  @ViewBuilder private var pin1Row: some View {
    if model.contents.hasPin1 {
      LabeledContent("PIN1") {
        Image(systemName: "checkmark")
          .foregroundStyle(.green)
          .accessibilityLabel("Stored")
      }
      .accessibilityIdentifier("pin1Status")
    } else {
      pin1Field
    }
  }

  /// The six printed digits, with the QR scanner beside them.
  @ViewBuilder private var cardAccessNumberField: some View {
    #if os(iOS)
      HStack {
        TextField(
          "Card Access Number (CAN)",
          text: LimitedDigitBinding.cardAccessNumber(
            $cardAccessNumberEntry)
        )
        .keyboardType(.numberPad)
        .accessibilityIdentifier("cardAccessNumberField")
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
      TextField(
        "Card Access Number (CAN)",
        text: LimitedDigitBinding.cardAccessNumber(
          $cardAccessNumberEntry)
      )
      .accessibilityIdentifier("cardAccessNumberField")
    #endif
  }

  @ViewBuilder private var pin1Field: some View {
    HStack {
      Group {
        if isPin1Revealed {
          TextField(
            "PIN1",
            text: LimitedDigitBinding.pin1($pin1Entry))
        } else {
          SecureField(
            "PIN1",
            text: LimitedDigitBinding.pin1($pin1Entry))
        }
      }
      #if os(iOS)
        .keyboardType(.numberPad)
        .textInputAutocapitalization(.never)
      #endif
      .autocorrectionDisabled()
      .focused($isPin1FieldFocused)
      .accessibilityIdentifier("pin1Field")

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

  private var diagnosticsSection: some View {
    Section {
      NavigationLink {
        DiagnosticsView()
      } label: {
        Label("Diagnostics", systemImage: "stethoscope")
      }
      .accessibilityIdentifier("diagnosticsButton")
    }
  }

  private var forgetSection: some View {
    Section {
      Button("Forget this card and identity", role: .destructive) {
        showsForgetConfirmation = true
      }
    }
  }

  #if os(iOS)
    /// The camera, framed so it can be dismissed.
    @ViewBuilder private var scannerSheet: some View {
      NavigationStack {
        CardAccessNumberScanner(
          torchEnabled: $scannerTorchEnabled
        ) { digits in
          scannerTorchEnabled = false
          cardAccessNumberEntry = digits
          isScanning = false
        }
        .ignoresSafeArea()
        .navigationTitle("Scan card QR code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { scannerToolbar }
      }
      .onDisappear {
        scannerTorchEnabled = false
      }
    }

    /// Dismissal and light controls kept above the live preview.
    @ToolbarContentBuilder private var scannerToolbar: some ToolbarContent {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          scannerTorchEnabled = false
          isScanning = false
        }
      }
      if CardAccessNumberScanner.hasTorch {
        ToolbarItem(placement: .primaryAction) {
          Button {
            scannerTorchEnabled.toggle()
          } label: {
            Label(
              scannerTorchEnabled ? "Turn light off" : "Turn light on",
              systemImage: scannerTorchEnabled
                ? "flashlight.on.fill" : "flashlight.off.fill")
          }
          .accessibilityIdentifier("cardAccessNumberScannerTorch")
        }
      }
    }
  #endif

  /// Stores the entered pair immediately before the NFC operation.
  @MainActor
  private func prepareIdentity() async -> Bool {
    let accessNumber =
      model.contents.hasCardAccessNumber ? nil : cardAccessNumberEntry
    let pin1 = model.contents.hasPin1 ? nil : pin1Entry

    cardAccessNumberEntry = ""
    pin1Entry = ""
    isPin1Revealed = false
    isPin1FieldFocused = false

    return await model.prepareIdentity(
      cardAccessNumber: accessNumber,
      pin1: pin1)
  }
}
