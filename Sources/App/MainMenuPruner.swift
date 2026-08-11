//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
#if os(macOS)

  import AppKit

  /// Removes top-level menus that ended up empty.
  ///
  /// SwiftUI materializes a View menu for its window scenes even when
  /// everything it would carry is compiled out or disabled, and offers
  /// no command placement for the menu itself. An empty menu offers
  /// nothing, so it goes at the AppKit layer. The main menu is rebuilt
  /// as scenes and windows change, so the pruning runs again on each
  /// launch, activation and main-window change rather than once.
  @MainActor
  internal enum MainMenuPruner {
    /// The subscriptions, held so they live as long as the app.
    private static var observers: [NSObjectProtocol] = []

    /// Begins watching the moments the main menu is (re)built.
    internal static func start() {
      let center = NotificationCenter.default
      for name in [
        NSApplication.didFinishLaunchingNotification,
        NSApplication.didBecomeActiveNotification,
        NSWindow.didBecomeMainNotification,
      ] {
        observers.append(
          center.addObserver(forName: name, object: nil, queue: .main) { _ in
            // On the main queue by request; hop the actor formally and
            // after the current menu rebuild has settled.
            Task { @MainActor in
              Self.prune()
            }
          }
        )
      }
    }

    /// Drops every top-level item whose submenu holds nothing.
    private static func prune() {
      guard let menu = NSApp.mainMenu else { return }
      for item in menu.items where item.submenu?.items.isEmpty == true {
        menu.removeItem(item)
      }
    }
  }

#endif
