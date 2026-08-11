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

  import SwiftUI

  /// Speaking an outcome that only appeared.
  ///
  /// A sentence that arrives in a window is read by whoever is looking
  /// at that part of the window. VoiceOver is not looking: focus stays
  /// where the holder left it, usually on the button they just pressed,
  /// and a failure drawn three rows below is never spoken. WCAG 4.1.3
  /// covers exactly this -- a status message must reach assistive
  /// technology without taking focus, because taking focus would move
  /// the holder away from what they were doing.
  ///
  /// The card windows are where it matters most. "That card access
  /// number was refused" and "PIN 2 is blocked" are the whole answer to
  /// what the holder just attempted, and a window that shows them in
  /// silence has told half its users nothing.
  extension View {
    /// Speaks each new value of a message, and says nothing when it
    /// clears.
    ///
    /// A cleared message is not an event: it is the absence of one, and
    /// announcing "" would interrupt for nothing.
    internal func announcesOutcome(_ message: String?) -> some View {
      onChange(of: message) { _, arrived in
        guard let arrived, !arrived.isEmpty else { return }
        AccessibilityNotification.Announcement(arrived).post()
      }
    }
  }

#endif
