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
#if os(iOS)
  import UIKit
#else
  import AppKit
#endif

/// Puts a diagnostics capture on the pasteboard, whichever pasteboard the
/// platform has.
///
/// A share sheet is the right way to send a trace to somebody else; the
/// pasteboard is the right way to get it into the text field, terminal or
/// note that is already open. Both exist because a capture that is
/// awkward to move is a capture nobody takes.
internal enum DiagnosticsClipboard {
  /// Replaces the pasteboard contents with `text`.
  ///
  /// Main-actor bound because both platform pasteboards are; the only
  /// caller is a button, which is already there.
  @MainActor
  internal static func copy(_ text: String) {
    #if os(iOS)
      UIPasteboard.general.string = text
    #else
      NSPasteboard.general.clearContents()
      _ = NSPasteboard.general.setString(text, forType: .string)
    #endif
  }
}
