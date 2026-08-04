#if os(macOS)

  import SwiftUI

  /// The Card menu: management that must not depend on card state.
  ///
  /// The status window shows what a present card answers; this menu is
  /// for what the holder must be able to do with no card readable at
  /// all, which today is managing the stored card access number.
  internal struct CardCommands: Commands {
    @Environment(\.openWindow)
    private var openWindow

    internal var body: some Commands {
      CommandMenu("Card") {
        Button("Sign a Document...") {
          openWindow(id: SignDocumentView.windowID)
        }
        Divider()
        Button("Card Access Number...") {
          openWindow(id: CardAccessNumberManagerView.windowID)
        }
        Button("PIN Management...") {
          openWindow(id: CardManagementView.windowID)
        }
        #if DEBUG
          Divider()
          Button("Diagnostics...") {
            openWindow(id: "diagnostics")
          }
        #endif
      }
    }
  }

#endif
