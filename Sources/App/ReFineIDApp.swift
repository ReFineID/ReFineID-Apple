import SwiftUI

/// Application entry point: one small status surface on every platform.
@main
internal struct ReFineIDApp: App {
  internal var body: some Scene {
    #if os(macOS)
      Window("ReFineID", id: "status") {
        StatusView()
      }
      .windowResizability(.contentSize)
    #else
      WindowGroup {
        // Only iOS reaches a card over NFC, and only the contactless
        // interface needs a card access number, so the credential screen
        // exists on iOS alone.
        // Setting the card up is what a holder comes here to do, so it
        // is what opens. What the card reports about itself is
        // diagnostic and sits one tap away.
        NavigationStack {
          CardCredentialsView()
        }
      }
    #endif
  }

  internal init() {
    TokenPublishProbe.runIfRequested()
    SignProbe.runIfRequested()
    CtkSignProbe.runIfRequested()
  }
}
