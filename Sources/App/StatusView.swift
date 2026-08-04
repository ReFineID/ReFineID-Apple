#if os(macOS)

  import AppKit
  import CardCore
  import SwiftUI
  import UniformTypeIdentifiers

  /// The Mac window: whether the card can log you in, and signing a
  /// document with it.
  ///
  /// It stays small. The login row does zero card I/O - it reads only
  /// what `ctkd` has already published, because an open session here
  /// once held the card while the token extension waited to sign, and
  /// hung a Safari login until the app was quit.
  ///
  /// Signing lives here rather than in a window of its own: dropping a
  /// document on the app is the thing a holder will try, and the app
  /// they dropped it on should be the one that signs it.
  internal struct StatusView: View {
    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 24
    private static let minimumWidth: CGFloat = 420
    private static let dropHeight: CGFloat = 96
    private static let dropSpacing: CGFloat = 6
    private static let noticeSpacing: CGFloat = 4
    private static let dropCornerRadius: CGFloat = 10
    private static let dropBorderWidth: CGFloat = 2

    @Environment(\.openWindow)
    private var openWindow

    private let model = LoginIdentityModel.shared
    @State private var signing = SignDocumentModel()
    @State private var pin2 = ""
    @State private var accessNumber = ""
    @State private var isTargeted = false
    @FocusState private var pinFocused: Bool

    /// Ready when a document is waiting and the entry could be a PIN2.
    private var canSign: Bool {
      signing.pending != nil && Self.isEntryComplete(pin2) && !signing.working
        // Not while the card is being read for the stamp: it is one
        // card, and asking it to sign mid-read is asking it to be in
        // two places.
        && !signing.readingStamp
    }

    /// What the identity row and the offered features key on.
    ///
    /// Reads two observed facts - the token's publication and the
    /// slot's physical answer - so the row moves the moment either
    /// does.
    private var availability: LoginIdentityModel.Availability {
      if model.isReady {
        .ready
      } else if CardPresence.shared.isCardPresent {
        .cardWithoutIdentity
      } else {
        .noCard
      }
    }

    internal var body: some View {
      VStack(alignment: .leading, spacing: Self.spacing) {
        Text(verbatim: "ReFineID")
          .font(.largeTitle.bold())
        Form {
          LabeledContent("Identity") {
            identityState
          }
          .accessibilityIdentifier("loginIdentityStatus")
          // No card, no card work: a drop target that cannot sign
          // and a PIN window over nothing are not features, they are
          // questions.
          if availability != .noCard {
            documentSection
            signatureSection
          }
          outcomeSection
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        if availability != .noCard {
          Button("PIN Management…") {
            openWindow(id: CardManagementView.windowID)
          }
          .accessibilityIdentifier("pinManagementButton")
        }
      }
      .padding(Self.padding)
      .frame(minWidth: Self.minimumWidth, alignment: .leading)
      .task { publishStoredNumber() }
      .onAppear {
        model.refresh()
        react(to: availability)
      }
      .onChange(of: availability) { _, now in
        react(to: now)
      }
    }

    /// Ready, or what to do about it - and the one state between,
    /// named honestly instead of asking for a card that is already
    /// in the reader.
    @ViewBuilder private var identityState: some View {
      switch availability {
      case .ready:
        Image(systemName: "checkmark")
          .foregroundStyle(.green)
          .accessibilityLabel("Ready")
      case .cardWithoutIdentity:
        Text("Card detected, not ready - if this lasts, re-insert it")
          .foregroundStyle(.orange)
      case .noCard:
        Text("Insert your card")
          .foregroundStyle(.secondary)
      }
    }

    /// The document to sign: dropped, or chosen.
    @ViewBuilder private var documentSection: some View {
      Section {
        dropContents
          .frame(maxWidth: .infinity, minHeight: Self.dropHeight)
          .contentShape(.rect)
          .overlay {
            if isTargeted {
              RoundedRectangle(cornerRadius: Self.dropCornerRadius)
                .strokeBorder(.tint, lineWidth: Self.dropBorderWidth)
            }
          }
          .dropDestination(for: URL.self) { urls, _ in
            accept(urls)
          } isTargeted: { targeted in
            isTargeted = targeted
          }
          .accessibilityLabel("Document to sign")
          .accessibilityValue(
            signing.pending?.lastPathComponent ?? "none chosen"
          )
      }
    }

    /// What the drop area shows: an invitation, or the chosen file.
    @ViewBuilder private var dropContents: some View {
      VStack(spacing: Self.dropSpacing) {
        Image(systemName: signing.pending == nil ? "doc.badge.plus" : "doc.text")
          .font(.title)
          .foregroundStyle(
            isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
          )
          .accessibilityHidden(true)
        if let pending = signing.pending {
          Text(pending.lastPathComponent)
            .lineLimit(1)
            .truncationMode(.middle)
          Button("Choose a different document…") { choose() }
            .buttonStyle(.link)
        } else {
          Text("Drop a PDF here to sign it")
            .foregroundStyle(.secondary)
          Button("Choose…") { choose() }
            .buttonStyle(.link)
            .accessibilityIdentifier("signChooseDocument")
        }
      }
    }

    /// PIN2, the optional stamp, and the action - shown once a
    /// document is waiting.
    @ViewBuilder private var signatureSection: some View {
      if signing.pending != nil {
        Section {
          SecureField("PIN2", text: $pin2)
            .onChange(of: pin2) { _, typed in
              pin2 = LimitedDigits.pin(typed)
            }
            .focused($pinFocused)
            .onSubmit { sign() }
            .accessibilityIdentifier("signPin2")
          StampRow(signing: signing, accessNumber: $accessNumber)
          HStack {
            Spacer()
            Button("Sign…") { sign() }
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
              .disabled(!canSign)
              .accessibilityIdentifier("signDocument")
          }
        }
        .onAppear { pinFocused = true }
      }
    }

    /// Progress, failure, or where the file went.
    @ViewBuilder private var outcomeSection: some View {
      if signing.working || signing.failure != nil || signing.signed != nil {
        Section {
          if signing.working {
            HStack(spacing: Self.dropSpacing) {
              ProgressView().controlSize(.small)
              Text("Signing: card, timestamp, revocation data…")
                .foregroundStyle(.secondary)
            }
          }
          if let failure = signing.failure {
            Text(failure)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
          if let note = signing.codeFailure {
            Text(note)
              .foregroundStyle(.orange)
              .textSelection(.enabled)
          }
          if let signed = signing.signed {
            VStack(alignment: .leading, spacing: Self.noticeSpacing) {
              Text("Signed: \(signed.lastPathComponent)")
                .foregroundStyle(.green)
                .textSelection(.enabled)
              Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([signed])
              }
              .buttonStyle(.link)
            }
          }
        }
      }
    }

    /// Whether an entry could be a PIN2 at all.
    private static func isEntryComplete(_ entry: String) -> Bool {
      (Pin2.minimumDigitCount...Pin2.maximumDigitCount).contains(entry.count)
    }

    /// Recovery follows the state: the unready state schedules one
    /// attempt, the card leaving resets the budget, ready stands
    /// down.
    private func react(to availability: LoginIdentityModel.Availability) {
      switch availability {
      case .ready:
        model.cancelRecovery(cardLeft: false)
      case .cardWithoutIdentity:
        model.attemptRecovery()
      case .noCard:
        model.cancelRecovery(cardLeft: true)
      }
    }

    /// Takes a dropped document, refusing anything that is not a PDF.
    private func accept(_ urls: [URL]) -> Bool {
      guard let url = urls.first else { return false }
      guard url.pathExtension.lowercased() == "pdf" else {
        signing.report(String(localized: "Only PDF documents can be signed."))
        return false
      }
      signing.accept(url)
      pin2 = ""
      pinFocused = true
      return true
    }

    /// Opens the chooser.
    private func choose() {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.pdf]
      panel.allowsMultipleSelection = false
      guard panel.runModal() == .OK, let url = panel.url else { return }
      signing.accept(url)
      pin2 = ""
      pinFocused = true
    }

    /// Asks where the signature goes, then signs.
    ///
    /// The panel runs here, from the button, and not inside the signing
    /// task: a modal panel raised from an async function blocks the
    /// main actor SwiftUI draws on, and a panel that never appears
    /// looks exactly like a button that does nothing.
    private func sign() {
      guard canSign, let source = signing.pending else { return }
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.pdf]
      panel.nameFieldStringValue = SignDocumentModel.suggestedName(for: source)
      panel.directoryURL = source.deletingLastPathComponent()
      panel.message = String(localized: "Where to keep the signed document.")
      panel.prompt = String(localized: "Sign")
      guard panel.runModal() == .OK, let destination = panel.url else {
        return
      }
      let entry = pin2
      pin2 = ""
      Task { await signing.sign(pin2: entry, to: destination) }
    }

    /// Hands the stored card access number to the driver, off the launch
    /// path.
    ///
    /// Reading the driver configuration is a synchronous call into
    /// `ctkd`, so it must not run where a slow or restarting `ctkd`
    /// would block the window before it can appear. It touches no card.
    private func publishStoredNumber() {
      Task.detached(priority: .utility) {
        CardCredentialStore.publishCardAccessNumberToDriver()
      }
    }
  }

#endif
