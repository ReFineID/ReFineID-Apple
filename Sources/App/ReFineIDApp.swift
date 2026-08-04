import CardCore
import SwiftUI

/// Application entry point: one small status surface on every platform.
@main
internal struct ReFineIDApp: App {
  internal var body: some Scene {
    #if os(macOS)
      Window("ReFineID", id: "status") {
        rootContent
      }
      .windowResizability(.contentSize)
      .commands { CardCommands() }

      Window("Card Access Number", id: CardAccessNumberManagerView.windowID) {
        CardAccessNumberManagerView()
          .writingToolsBehavior(.disabled)
      }
      .windowResizability(.contentSize)

      Window("PIN Management", id: CardManagementView.windowID) {
        CardManagementView()
          .writingToolsBehavior(.disabled)
      }
      .windowResizability(.contentSize)

      Settings {
        TabView {
          TimestampAuthoritiesSettingsView()
            .writingToolsBehavior(.disabled)
            .tabItem {
              Label("Time-Stamp Authorities", systemImage: "clock.badge.checkmark")
            }
        }
      }

      // Development builds only: the release configurations exclude the
      // diagnostics sources at file level, so the scene must not exist
      // there either.
      #if DEBUG
        Window("Diagnostics", id: "diagnostics") {
          NavigationStack {
            DiagnosticsView()
          }
        }
        .windowResizability(.contentSize)
      #endif
    #else
      WindowGroup {
        rootContent
      }
    #endif
  }

  /// What the window holds.
  ///
  /// A debug build launched with a scene-bound debug mode roots the window
  /// in that mode's runner instead of the app: the mode needs a foreground
  /// window to open an NFC slot or present a prompt, and it exits the
  /// process when it is done. Nothing of that exists in a release build.
  /// Writing Tools may not touch this app's text.
  ///
  /// Every text field here holds a credential or a service address: a
  /// PIN, a PUK, a card access number, a timestamp authority. Writing
  /// Tools offers to rewrite, summarise and proofread what is in them,
  /// which means handing it to a language model - and "Make Friendly"
  /// beside a PUK field is an offer no holder should be shown, let
  /// alone accept. Disabling it at the root reaches every field in
  /// every window.
  @ViewBuilder private var rootContent: some View {
    contentForLaunchMode
      .writingToolsBehavior(.disabled)
  }

  /// The screen for this launch, before the app-wide modifiers.
  @ViewBuilder private var contentForLaunchMode: some View {
    #if DEBUG
      if let mode = DebugLaunchModes.sceneMode {
        DebugSceneRunnerView(mode: mode)
      } else {
        holderContent
      }
    #else
      holderContent
    #endif
  }

  /// The screen a holder actually came here for.
  @ViewBuilder private var holderContent: some View {
    #if os(macOS)
      StatusView()
    #else
      // A successfully minted USB-C token owns the app while its reader
      // remains connected. Otherwise the phone offers the one-time NFC
      // identity setup.
      ReaderIdentityRootView()
    #endif
  }

  internal init() {
    // Builds with the retired fifteen-minute policy wrote a second PIN1
    // item. Nothing reads it now, so remove it on the first launch after
    // an upgrade rather than leave sensitive dead data in the keychain.
    CardCredentialStore.removeLegacySigningWindow()

    // A hold marks the next NFC field as its own registration field, and
    // clears the mark when it ends. A hold that never ends -- the app
    // killed with the panel up -- leaves the mark behind, and while it
    // stands a signing field publishes without taking the card session
    // it needs, so the signature that follows fails with TKError -7.
    // Nothing is being held at launch, so anything left here is stale.
    PrimeStore.clearRegistrationField()

    // Nothing that talks to another process belongs here. Handing the
    // card access number to the driver was done from this initializer
    // and it hung the app: reading the driver configuration is a
    // synchronous call into `ctkd`, so whenever `ctkd` was slow or
    // restarting the app blocked before it had a window to say so in.
    // It happens off the launch path now, from the status screen.
    //
    // One entry point for every launch mode, and it lives behind DEBUG.
    // A shipped binary has no business offering to drive a signature,
    // least of all one that takes a PIN on the command line.
    #if DEBUG
      DebugLaunchModes.runBeforeScene()
    #endif
  }
}
