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
      }
      .windowResizability(.contentSize)

      Window("Card Management", id: CardManagementView.windowID) {
        CardManagementView()
      }
      .windowResizability(.contentSize)
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
  @ViewBuilder private var rootContent: some View {
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
