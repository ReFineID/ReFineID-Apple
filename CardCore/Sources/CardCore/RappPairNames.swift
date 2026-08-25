// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// App-side names for paired devices, keyed by pair identifier.
///
/// The pair record binds no display name; the reviewed peer's name is
/// remembered here so the paired list can say which device it is.
public enum RappPairNames: Sendable {
  // MARK: Static Properties

  private static let key = "fi.refineid.rapp.pair-names"
  private static let lock = NSLock()

  // MARK: Public API

  /// Remembers the reviewed peer's name for one completed pair.
  public static func remember(_ name: String, pairID: Data) {
    lock.lock()
    defer { lock.unlock() }
    var names = stored()
    names[pairID.base64EncodedString()] = name
    UserDefaults.standard.set(names, forKey: key)
  }

  /// The remembered name, or nil for a pair completed before names
  /// were kept.
  public static func name(forPairID pairID: Data) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return stored()[pairID.base64EncodedString()]
  }

  /// Drops the name of a removed pair.
  public static func forget(pairID: Data) {
    lock.lock()
    defer { lock.unlock() }
    var names = stored()
    names.removeValue(forKey: pairID.base64EncodedString())
    UserDefaults.standard.set(names, forKey: key)
  }

  /// Drops every remembered name, orphans included.
  public static func forgetAll() {
    lock.lock()
    defer { lock.unlock() }
    UserDefaults.standard.removeObject(forKey: key)
  }

  // MARK: Private Helpers

  private static func stored() -> [String: String] {
    UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
  }
}
