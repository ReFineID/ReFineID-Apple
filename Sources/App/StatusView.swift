#if os(macOS)

  import CardCore
  import SwiftUI

  /// The Mac window: whether the card can log you in, and nothing else.
  ///
  /// It is deliberately as small as the phone's setup screen. On a
  /// contact reader there is nothing to configure -- no card access
  /// number, no PIN to store, no identity to mint -- so the only thing a
  /// holder needs from this window is whether the card is ready. Reader
  /// names, PIN attempt counters and card generations were removed
  /// rather than moved: they answered questions nobody had, in a window
  /// that has to be trustworthy at a glance.
  ///
  /// Removing them also removed a fault. Every one of those rows needed
  /// an exclusive card session, and a card is exclusive: with this
  /// window open the token extension's signature waited for the app to
  /// let go, which no protocol timer bounds. It hung a Safari login
  /// until the app was quit. This window now reads only what `ctkd` has
  /// already published, so it cannot take the card away from a login.
  ///
  /// The detailed card probe still exists, in Diagnostics, behind the
  /// Card menu in a development build - never in this window.
  internal struct StatusView: View {
    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 24
    private static let minimumWidth: CGFloat = 420
    private static let dropCornerRadius: CGFloat = 12
    private static let dropBorderWidth: CGFloat = 2

    @Environment(\.openWindow)
    private var openWindow

    @State private var model = LoginIdentityModel()
    @State private var isTargeted = false

    internal var body: some View {
      VStack(alignment: .leading, spacing: Self.spacing) {
        Text(verbatim: "ReFineID")
          .font(.largeTitle.bold())
        Form {
          LabeledContent("Login identity") {
            identityState
          }
          .accessibilityIdentifier("loginIdentityStatus")
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("Sign a Document...") {
            openWindow(id: SignDocumentView.windowID)
          }
          .accessibilityIdentifier("signDocumentButton")
          Button("PIN Management...") {
            openWindow(id: CardManagementView.windowID)
          }
          .accessibilityIdentifier("pinManagementButton")
        }
      }
      .padding(Self.padding)
      .frame(minWidth: Self.minimumWidth, alignment: .leading)
      .contentShape(.rect)
      .dropDestination(for: URL.self) { urls, _ in
        accept(urls)
      } isTargeted: { targeted in
        isTargeted = targeted
      }
      .overlay {
        if isTargeted {
          RoundedRectangle(cornerRadius: Self.dropCornerRadius)
            .strokeBorder(.tint, lineWidth: Self.dropBorderWidth)
        }
      }
      .task { publishStoredNumber() }
      .onAppear { model.refresh() }
    }

    /// Ready, or what to do about it.
    ///
    /// A checkmark for ready, matching the phone, and otherwise the one
    /// action that helps. There is no third state worth a row: anything
    /// finer belongs to Diagnostics.
    @ViewBuilder private var identityState: some View {
      if model.isReady {
        Image(systemName: "checkmark")
          .foregroundStyle(.green)
          .accessibilityLabel("Ready")
      } else {
        Text("Insert your card")
          .foregroundStyle(.secondary)
      }
    }

    /// Takes a document dropped anywhere on the window and opens the
    /// signing window holding it.
    ///
    /// Dropping on the app's own window is what a holder will try
    /// first, so it has to mean the same as dropping on the signing
    /// window itself.
    private func accept(_ urls: [URL]) -> Bool {
      guard let url = urls.first, url.pathExtension.lowercased() == "pdf" else {
        return false
      }
      SignDocumentModel.shared.accept(url)
      openWindow(id: SignDocumentView.windowID)
      return true
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

  #Preview {
    StatusView()
  }

#endif
