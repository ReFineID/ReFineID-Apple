// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

/// Application entry point: one small status surface on every platform.
@main
internal struct ReFineIDApp: App {
  #if os(macOS) && FEATURE_CONTACTLESS
    /// Keeps the quit-time observer alive for the process's lifetime.
    ///
    /// Registration hands an observer back, and it is never removed:
    /// quitting is the moment it exists for.
    @MainActor
    private enum QuitWithdrawal {
      static var observer: NSObjectProtocol?
    }
  #endif

  #if os(iOS)
    /// Catches the Home Screen action that starts a demonstration.
    ///
    /// The app has no other use for an application delegate; this one
    /// exists to be where a quick action arrives. What is done with it is
    /// in ``DemoModeShortcut``.
    @UIApplicationDelegateAdaptor(DemoModeAppDelegate.self)
    private var demoModeDelegate
    @State private var showsVirtualCardEditor = false
  #endif

  internal var body: some Scene {
    #if os(macOS)
      Window("ReFineID", id: "status") {
        rootContent
          .windowFullScreenBehavior(.disabled)
      }
      .windowResizability(.contentSize)
      // No help book ships, so the Help menu it would open does not
      // belong. Replacing the group with nothing leaves the menu with
      // no item, and MainMenuPruner removes the empty shell.
      .commands {
        CommandGroup(replacing: .help) {
          // Intentionally empty: no help item, so no Help menu.
        }
      }

      Settings {
        ReFineIDSettingsView()
          .writingToolsBehavior(.disabled)
          .windowFullScreenBehavior(.disabled)
      }

      // Development builds only: the release configurations exclude the
      // diagnostics sources at file level, so the scene must not exist
      // there either.
      #if DEBUG
        Window("Diagnostics", id: "diagnostics") {
          NavigationStack {
            DiagnosticsView()
          }
          .windowFullScreenBehavior(.disabled)
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
      ZStack(alignment: .bottomTrailing) {
        ReaderIdentityRootView()
          .accessibilityHidden(showsVirtualCardEditor)
          .allowsHitTesting(!showsVirtualCardEditor)
        if showsVirtualCardEditor {
          VirtualIDCardEditor(demoMode: DemoMode.shared) {
            showsVirtualCardEditor = false
            DemoMode.shared.setEditorPresented(false)
            NotificationCenter.default.post(
              name: .virtualIDCardEditorDidDismiss,
              object: nil)
          }
          .zIndex(2)
        } else {
          if DemoMode.shared.isActive {
            VirtualIDCardOverlay {
              DemoMode.shared.setEditorPresented(true)
              showsVirtualCardEditor = true
            }
              // Keep the overlay's hit-test surface on the floating control;
              // the parent overlay otherwise accepts the root view's full
              // proposal and can shield the product UI underneath it.
              .fixedSize()
          }
        }
      }
    #endif
  }

  internal init() {
    // Before anything else: this launch becomes the only running
    // copy. Different bundle paths - /Applications beside a build
    // from Xcode - are different apps to LaunchServices, so nothing
    // else enforces it.
    #if os(macOS)
      SingleInstance.enforce()

      // Every text field here holds digits or a service address:
      // the character palette composes prose and dictation sends what
      // is spoken to a speech service, so neither belongs in the Edit
      // menu here. AppKit honours these as user defaults - not as
      // Info.plist keys - by leaving the items out.
      UserDefaults.standard.set(
        true, forKey: "NSDisabledCharacterPaletteMenuItem"
      )
      UserDefaults.standard.set(
        true, forKey: "NSDisabledDictationMenuItem"
      )

      // AppKit inserts "Enter Full Screen" into a View menu on its
      // own; windowFullScreenBehavior only stops the window itself.
      // This default keeps the item - and with it the whole View
      // menu - from being created for fixed-size windows.
      UserDefaults.standard.set(
        false, forKey: "NSFullScreenMenuItemEverywhere"
      )

      // What that leaves behind is an empty View menu shell, which
      // SwiftUI offers no way to decline; it is pruned as AppKit
      // rebuilds the menu.
      MainMenuPruner.start()
    #endif

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
    // The localhost SCS: web pages sign through it, so it lives for
    // as long as the app runs. Binding a loopback socket touches no
    // other process, so unlike the driver configuration above this
    // is safe on the launch path; the PIN prompts it may later show
    // run on their own worker exchanges. Behind its feature: the MVP
    // ships without it, so a first launch binds no socket and asks
    // for no localhost-certificate trust.
    #if os(macOS)
      #if FEATURE_SCS
        ScsService.startIfNeeded()
      #endif

      // The offered access number lives for the app run: the status
      // screen withdraws a stale one at launch, and this withdraws
      // the current one at quit. Only with the feature: without it no
      // number is offered, and there is no group container to reach.
      #if FEATURE_CONTACTLESS
        QuitWithdrawal.observer = NotificationCenter.default.addObserver(
          forName: NSApplication.willTerminateNotification,
          object: nil,
          queue: nil
        ) { _ in
          CardCredentialStore.withdrawCardAccessNumberFromDriver()
        }
      #endif
    #endif

    // One entry point for every launch mode, and it lives behind DEBUG.
    // A shipped binary has no business offering to drive a signature,
    // least of all one that takes a PIN on the command line.
    #if DEBUG
      DebugLaunchModes.runBeforeScene()
    #endif

    #if os(iOS) && DEBUG
      DemoMode.shared.activateFromLaunchArguments()
    #endif
  }
}
