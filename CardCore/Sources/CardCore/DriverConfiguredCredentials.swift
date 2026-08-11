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

import CryptoTokenKit
import Foundation
import ObjCExceptionGuard

/// The app's view of CryptoTokenKit's configuration store for its own
/// token driver.
///
/// The store no longer carries the card access number.
/// `driverConfigurations` is populated for the hosting application
/// only - every other caller, the token driver itself included, is
/// handed an empty store - so a number written here was unreadable
/// exactly where it was needed. `OfferedAccessNumber` carries it now,
/// through the app group container both processes can read.
///
/// What remains here is the store as the system lists it: the named
/// entry earlier versions published, withdrawn so it does not outlive
/// them, and the identity configurations the debug reset drops.
public enum DriverConfiguredCredentials {
  /// The driver whose configuration this is: `com.apple.ctk.class-id`
  /// in the token extension's Info.plist.
  private static let classID = CardTokenNamespace.driverClassIdentifier

  /// Names the one entry this app keeps.
  ///
  /// A fixed name rather than a card's identifier, because the card
  /// access number this Mac holds is a single stored value -- the same
  /// one the keychain keeps under a single account -- and because a card
  /// answers with a different identifier on each of its two interfaces,
  /// so keying by card would need the number stored once per interface
  /// to be found from either.
  ///
  /// Public because of what it costs: every token configuration is keyed
  /// by an instance identifier, and
  /// the system lists those identifiers as tokens whether or not a token
  /// was ever created for one. This entry therefore appears alongside
  /// real cards in `TKTokenWatcher`, holding no keychain items and so
  /// offering nothing to Safari -- but anything asking "is a card
  /// available?" has to exclude it by name, or it answers yes with no
  /// card present.
  public static let configurationInstanceID = "card-access-number"

  /// The configuration store, or nil in a process that is not the
  /// driver's hosting application.
  ///
  /// Read through the exception guard: the store is an XPC call into
  /// `ctkd`, and a daemon mid-restart can answer it with an
  /// Objective-C exception instead of a value. Caught, that answer
  /// becomes what it means here - no store readable right now.
  private static var configuration: TKTokenDriver.Configuration? {
    var stores: [String: TKTokenDriver.Configuration] = [:]
    let raised = CardCoreCatchException {
      stores = TKTokenDriver.Configuration.driverConfigurations
    }
    guard raised == nil else { return nil }
    return stores[Self.classID]
  }

  /// Drops every token configuration except this app's own credential
  /// entry, and answers how many went.
  ///
  /// Destructive, and not a recovery: "everything except ours" includes
  /// the configuration the system keeps for the card that is working
  /// right now, so calling this unregisters a live token. It was briefly
  /// wired into the status screen's refresh as a nudge, where it
  /// unregistered a card seconds after a successful login and then
  /// reported the card missing.
  ///
  /// It is for the debug reset, which exists to leave nothing behind.
  /// Anything offering recovery to a holder has to tell a dead
  /// registration from a live one by something other than ownership.
  public static func dropEveryTokenConfiguration() -> Int {
    guard let configuration else { return 0 }
    let stale = configuration.tokenConfigurations.keys.filter { instance in
      instance != Self.configurationInstanceID
    }
    for instance in stale {
      configuration.removeTokenConfiguration(for: instance)
    }
    return stale.count
  }

  /// Drops only card-identity configurations, preserving stored setup.
  ///
  /// The driver class is ReFineID's private namespace, so every entry
  /// except the two named setup channels is an identity published by
  /// this app or an earlier version of it. This deliberately catches
  /// legacy ATR-hash instance names as well as current
  /// `refineid-card-*` names without touching another driver's tokens.
  public static func dropIdentityTokenConfigurations() -> Int {
    guard let configuration else { return 0 }
    let identities = Self.identityTokenConfigurationIDs(in: configuration)
    for instance in identities {
      configuration.removeTokenConfiguration(for: instance)
    }
    return identities.count
  }

  /// How many card identities this driver configuration still holds.
  ///
  /// Presence only. The setup screen uses this to offer its destructive
  /// forget action for a stale partial identity without reading a token,
  /// touching a card, or exposing configuration data.
  public static func identityTokenConfigurationCount() -> Int {
    guard let configuration else { return 0 }
    return Self.identityTokenConfigurationIDs(in: configuration).count
  }

  /// Identity instance names, excluding the setup-only channel.
  private static func identityTokenConfigurationIDs(
    in configuration: TKTokenDriver.Configuration
  ) -> [String] {
    configuration.tokenConfigurations.keys.filter { instance in
      instance != Self.configurationInstanceID
    }
  }

  /// Withdraws it, so forgetting the card forgets it here too.
  internal static func withdraw() {
    configuration?.removeTokenConfiguration(for: Self.configurationInstanceID)
  }
}
