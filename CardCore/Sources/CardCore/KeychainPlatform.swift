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
import Foundation

/// Which keychain the card stores use on this platform.
///
/// iOS uses the data-protection keychain, which is what makes an item
/// device-only and non-syncable in the way the card secrets need.
///
/// macOS cannot: the data-protection keychain there requires a
/// `keychain-access-groups` entitlement, and a development-signed build
/// cannot carry one -- every store call then answers
/// `errSecMissingEntitlement` and the app can keep nothing at all. The
/// file keychain needs no entitlement and is protected by the login
/// keychain the rest of the system already uses. The trade is recorded
/// here rather than repeated at five call sites.
internal enum KeychainPlatform {
  /// Whether `kSecUseDataProtectionKeychain` may be requested.
  internal static var usesDataProtection: Bool {
    #if os(iOS)
      true
    #else
      false
    #endif
  }
}
