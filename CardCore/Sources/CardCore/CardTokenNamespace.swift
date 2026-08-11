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
/// The CryptoTokenKit namespace owned by ReFineID.
///
/// The driver class identifier is fixed by the extension manifest. Keeping
/// its token-ID spelling here gives the app and extension one source of truth
/// for registration, status, and revocation.
public enum CardTokenNamespace {
  /// The token driver's class identifier.
  public static let driverClassIdentifier = "fi.refineid.ReFineID.token"

  /// Driver class identifiers shipped by older ReFineID builds.
  ///
  /// They no longer create tokens, but a persistent Safari registration
  /// can outlive the build that created it. Destructive ReFineID cleanup
  /// owns these registrations too; it must not mistake "old" for
  /// "somebody else's".
  private static let legacyDriverClassIdentifiers = [
    "fi.refineid.ReFineID.ctk"
  ]

  /// CryptoTokenKit separates the class and instance identifiers with this.
  private static let identifierSeparator = ":"

  /// Prefix shared by every ReFineID smart-card token identifier.
  public static let tokenPrefix = driverClassIdentifier + identifierSeparator

  /// Every token prefix ever issued by ReFineID.
  private static let ownedTokenPrefixes =
    ([driverClassIdentifier] + legacyDriverClassIdentifiers)
    .map { $0 + identifierSeparator }

  /// The full CryptoTokenKit token identifier for one physical card.
  public static func tokenIdentifier(for instance: CardInstanceIdentifier) -> String {
    tokenPrefix + instance.value
  }

  /// Whether a full token identifier belongs to this driver.
  public static func owns(tokenIdentifier: String) -> Bool {
    ownedTokenPrefixes.contains { tokenIdentifier.hasPrefix($0) }
  }
}
