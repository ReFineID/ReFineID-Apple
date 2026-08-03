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
  /// The detailed card probe still exists, in Diagnostics, where it is
  /// an explicit action in a development build.
  internal struct StatusView: View {
    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 24
    private static let minimumWidth: CGFloat = 420

    @State private var model = LoginIdentityModel()

    #if DEBUG
      @State private var showsDiagnostics = false
    #endif

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
        #if DEBUG
          diagnosticsButton
        #endif
      }
      .padding(Self.padding)
      .frame(minWidth: Self.minimumWidth, alignment: .leading)
      .task { publishStoredNumber() }
      .onAppear { model.refresh() }
      #if DEBUG
        .sheet(isPresented: $showsDiagnostics) {
          NavigationStack {
            DiagnosticsView()
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Done") { showsDiagnostics = false }
              }
            }
          }
        }
      #endif
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

    #if DEBUG
      /// Development-only, and under everything else for that reason.
      private var diagnosticsButton: some View {
        Button {
          showsDiagnostics = true
        } label: {
          Label("Diagnostics", systemImage: "stethoscope")
        }
        .accessibilityIdentifier("diagnosticsButton")
      }
    #endif

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
