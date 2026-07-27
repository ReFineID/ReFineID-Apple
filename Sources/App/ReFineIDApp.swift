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
      // Only iOS reaches a card over NFC, and only the contactless
      // interface needs a card access number, so the credential screen
      // exists on iOS alone.
      // Setting the card up is what a holder comes here to do, so it
      // is what opens. What the card reports about itself is
      // diagnostic and sits one tap away.
      NavigationStack {
        CardCredentialsView()
      }
    #endif
  }

  internal init() {
    // The driver cannot read the keychain item holding the card access
    // number on macOS, so the app hands it over on every launch. Doing it
    // here rather than only where the number is entered is what reaches a
    // number that was stored before this channel existed.
    CardCredentialStore.publishCardAccessNumberToDriver()
    // One entry point for every launch mode, and it lives behind DEBUG.
    // A shipped binary has no business offering to drive a signature,
    // least of all one that takes a PIN on the command line.
    #if DEBUG
      DebugLaunchModes.runBeforeScene()
    #endif
  }
}
