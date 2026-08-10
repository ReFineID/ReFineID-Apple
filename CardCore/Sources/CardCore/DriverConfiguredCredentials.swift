import CryptoTokenKit
import Foundation
import ObjCExceptionGuard

/// The card access number as the app hands it to its own token driver,
/// through CryptoTokenKit's configuration store.
///
/// macOS leaves the two processes no keychain to share. An item created
/// there carries an access list naming the application that created it,
/// and a token extension is a different application: it finds the item
/// and is refused the value with `errSecInteractionNotAllowed`, which it
/// cannot resolve, because a driver hosted by `ctkd` has no interface to
/// authorize with. A shared keychain access group is the usual answer
/// and is what iOS uses here, but it is a restricted entitlement that
/// the signing profile has to carry.
///
/// CryptoTokenKit provides a channel for this and documents it for
/// exactly this purpose: a token configuration carries data that the
/// token implementation and its hosting application both use, that the
/// system does not interpret, and whose documented example is access
/// credentials. Only the hosting application can write it -- every other
/// caller is handed an empty store -- so the driver's own app bundle is
/// the boundary, without an entitlement.
///
/// The digits never pass through a caller. They are read from the
/// keychain and written here inside `CardCredentialStore`, which is the
/// same reason that type assembles primes itself.
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

  /// The published digits as raw bytes, for fingerprinting only.
  ///
  /// `CardCredentialStore.cardAccessNumberFingerprint` digests these so
  /// the driver can remember "this number was refused" without holding
  /// digits; nothing else may read this.
  internal static func digitsData() -> Data? {
    configuration?.tokenConfigurations[Self.configurationInstanceID]?.configurationData
  }

  /// The card access number the app published, if any.
  internal static func cardAccessNumber() -> CardAccessNumber? {
    guard
      let entry = configuration?.tokenConfigurations[Self.configurationInstanceID],
      let data = entry.configurationData,
      let digits = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return CardAccessNumber(digits: digits)
  }

  /// Publishes `digits` for the driver to read, replacing what was there.
  ///
  /// Answers whether the store took it, which is false in any process
  /// that does not host the driver.
  internal static func publish(digits: String) -> Bool {
    guard let configuration else { return false }
    let token = configuration.addTokenConfiguration(for: Self.configurationInstanceID)
    token.configurationData = Data(digits.utf8)
    return true
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
