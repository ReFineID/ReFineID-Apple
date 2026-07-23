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
        StatusView()
      }
    #endif
  }

  internal init() {
    TokenPublishProbe.runIfRequested()
    SignProbe.runIfRequested()
    CtkSignProbe.runIfRequested()
  }
}
