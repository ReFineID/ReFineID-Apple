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

  import Foundation

  /// The keys the app's runtime settings live under, in one place so a
  /// window and the Settings pane bind the same stored value.
  ///
  /// `UserDefaults`-backed through `@AppStorage`; a change in Settings
  /// reaches every window that reads the key.
  internal enum AppSettings {
    /// Whether contactless cards are served: the CAN entry appears and
    /// numbers are offered only when this is on.
    ///
    /// Off by default. Contactless is the rare case - a card presented
    /// on the antenna rather than inserted - and the holder who wants
    /// it turns it on in Settings; contact readers need no setting.
    internal static let contactlessEnabled = "contactlessEnabled"
  }

#endif
