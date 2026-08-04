#if os(macOS)

  import SwiftUI

  /// The Card menu: management that must not depend on card state.
  ///
  /// The status window shows what a present card answers; this menu is
  /// for what the holder must be able to do with no card readable at
  /// all, which today is managing the stored card access number.
  ///
  /// The timestamp authorities are settings, and macOS keeps settings
  /// under the app menu - they are not windows and do not belong in the
  /// Window menu. But nobody looking for which service stamps their
  /// signature would think to look in Settings, so the menu that holds
  /// the rest of the card work offers a way straight to that pane.
  internal struct CardCommands: Commands {
    @Environment(\.openWindow)
    private var openWindow

    internal var body: some Commands {
      CommandMenu("Card") {
        Button("Card Access Number…") {
          openWindow(id: CardAccessNumberManagerView.windowID)
        }
        // Disabled rather than hidden: menus keep their shape, and a
        // grayed item says why it cannot be used - no card.
        Button("PIN Management…") {
          openWindow(id: CardManagementView.windowID)
        }
        .disabled(!CardPresence.shared.isCardPresent)
        Divider()
        SettingsLink {
          Text("Time-Stamp Authorities…")
        }
        #if DEBUG
          Divider()
          Button("Diagnostics…") {
            openWindow(id: "diagnostics")
          }
        #endif
      }
    }
  }

#endif
