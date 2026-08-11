// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
#if os(macOS)
  import AppKit
  import CardCore
  import Foundation

  /// The PIN prompt the localhost SCS presents.
  ///
  /// SCS signs arrive from a web page, not from CryptoTokenKit, so
  /// the app itself asks for the credential. The prompt runs on the
  /// main thread and blocks the SCS worker until the holder answers;
  /// cancelling refuses the sign without touching the card.
  internal enum ScsPinPrompt {
    private static let fieldWidth: CGFloat = 220
    private static let fieldHeight: CGFloat = 24

    /// Asks for the named credential; nil when the holder cancels.
    internal static func request(role: CredentialRole) -> String? {
      var answer: String?
      DispatchQueue.main.sync {
        MainActor.assumeIsolated {
          answer = Self.presentPrompt(role: role)
        }
      }
      return answer
    }

    /// Builds and runs the modal alert; main thread only.
    @MainActor
    private static func presentPrompt(role: CredentialRole) -> String? {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText =
        role == .pin1
        ? "Enter PIN 1 for the signing service"
        : "Enter PIN 2 (signature) for the signing service"
      alert.informativeText =
        "A web page is requesting a card signature through the local "
        + "signing service (SCS)."
      let field = NSSecureTextField(
        frame: NSRect(x: 0, y: 0, width: Self.fieldWidth, height: Self.fieldHeight))
      alert.accessoryView = field
      alert.addButton(withTitle: "Sign")
      alert.addButton(withTitle: "Cancel")
      alert.window.initialFirstResponder = field
      guard alert.runModal() == .alertFirstButtonReturn else { return nil }
      return field.stringValue
    }
  }
#endif
