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
import Foundation

/// How the card PIN is collected, selected by REFINEID_PKCS11_PIN_ENTRY.
///
/// Graphical entry is the default: the token advertises
/// CKF_PROTECTED_AUTHENTICATION_PATH, so the consumer does not prompt
/// and the system dialog collects the PIN when the card signs, which
/// keeps it out of the consumer process. Textual entry withdraws the
/// flag, leaving the consumer to prompt for the PIN -- on its terminal
/// for ssh -- which is the only way to use the card over a remote or
/// headless session, where no dialog can be answered.
package enum PinEntry {
  case graphical
  case textual

  /// The environment variable selecting the mode.
  package static let variable = "REFINEID_PKCS11_PIN_ENTRY"

  /// The variable value selecting textual entry; every other value,
  /// including "graphical", leaves the default in place.
  package static let textualValue = "textual"

  /// The mode the current environment selects.
  package static var current: Self {
    resolve(ProcessInfo.processInfo.environment[variable])
  }

  /// The mode a variable value selects, compared case-insensitively.
  ///
  /// An unset or unrecognized value keeps the default, so a typo
  /// cannot silently move PIN entry out of the system dialog.
  package static func resolve(_ value: String?) -> Self {
    value?.lowercased() == textualValue ? .textual : .graphical
  }
}
