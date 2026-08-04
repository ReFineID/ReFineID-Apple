#if os(macOS)

  import CardCore
  import SwiftUI
  import UniformTypeIdentifiers

  /// The signing window: drop a PDF, enter PIN2, get an archival
  /// signature beside the original.
  internal struct SignDocumentView: View {
    /// Window identity, for the menu command that opens it.
    internal static let windowID = "sign-document"

    private static let windowWidth: CGFloat = 460
    private static let dropHeight: CGFloat = 120
    private static let stackSpacing: CGFloat = 8
    private static let noticeSpacing: CGFloat = 4

    @State private var model = SignDocumentModel()
    @State private var pin2 = ""
    @State private var isTargeted = false
    @FocusState private var pinFocused: Bool

    /// Ready when a document is waiting and the entry could be a PIN2.
    private var canSign: Bool {
      model.pending != nil
        && (Pin2.minimumDigitCount...Pin2.maximumDigitCount).contains(pin2.count)
        && !model.working
    }

    internal var body: some View {
      Form {
        dropSection
        if model.pending != nil {
          signSection
        }
        outcomeSection
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.windowWidth)
    }

    /// The drop target, and what is on it.
    @ViewBuilder private var dropSection: some View {
      Section {
        VStack(spacing: Self.stackSpacing) {
          Image(systemName: model.pending == nil ? "doc.badge.plus" : "doc.text")
            .font(.largeTitle)
            .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
          if let pending = model.pending {
            Text(pending.lastPathComponent)
              .lineLimit(1)
              .truncationMode(.middle)
            Button("Choose a different document...") { choose() }
              .buttonStyle(.link)
          } else {
            Text("Drop a PDF here, or choose one")
              .foregroundStyle(.secondary)
            Button("Choose...") { choose() }
              .accessibilityIdentifier("signChooseDocument")
          }
        }
        .frame(maxWidth: .infinity, minHeight: Self.dropHeight)
        .contentShape(.rect)
        .onDrop(of: [.pdf], isTargeted: $isTargeted) { providers in
          accept(providers)
        }
        .accessibilityLabel("Document to sign")
        .accessibilityValue(model.pending?.lastPathComponent ?? "none chosen")
      }
    }

    /// PIN2 and the action.
    @ViewBuilder private var signSection: some View {
      Section {
        SecureField("PIN2", text: $pin2)
          .onChange(of: pin2) { _, typed in
            pin2 = LimitedDigits.pin(typed)
          }
          .focused($pinFocused)
          .onSubmit { sign() }
          .accessibilityIdentifier("signPin2")
        Text(
          "The signature is archival (PAdES-B-LTA): it fetches a "
            + "qualified timestamp and revocation data, so it stays "
            + "verifiable after the certificates expire."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        HStack {
          Spacer()
          Button("Sign") { sign() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSign)
            .accessibilityIdentifier("signDocument")
        }
      }
      .onAppear { pinFocused = true }
    }

    /// Progress, failure, or where the file went.
    @ViewBuilder private var outcomeSection: some View {
      if model.working || model.failure != nil || model.signed != nil {
        Section {
          if model.working {
            HStack(spacing: Self.stackSpacing) {
              ProgressView().controlSize(.small)
              Text("Signing: card, timestamp, revocation data...")
                .foregroundStyle(.secondary)
            }
          }
          if let failure = model.failure {
            Text(failure)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
          if let signed = model.signed {
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

    /// Takes the first dropped PDF.
    private func accept(_ providers: [NSItemProvider]) -> Bool {
      guard let provider = providers.first else { return false }
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url else { return }
        Task { @MainActor in
          model.accept(url)
          pin2 = ""
        }
      }
      return true
    }

    /// Opens the chooser.
    private func choose() {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.pdf]
      panel.allowsMultipleSelection = false
      guard panel.runModal() == .OK, let url = panel.url else { return }
      model.accept(url)
      pin2 = ""
    }

    /// Signs, clearing the entry whatever the outcome.
    private func sign() {
      guard canSign else { return }
      let entry = pin2
      pin2 = ""
      Task { await model.sign(pin2: entry) }
    }
  }

#endif
