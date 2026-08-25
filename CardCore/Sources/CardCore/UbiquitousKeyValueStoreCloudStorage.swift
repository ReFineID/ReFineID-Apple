// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Production iCloud Key-Value store implementation.
public final class UbiquitousKeyValueStoreCloudStorage: RappCloudStorage, @unchecked Sendable {
  private let store: NSUbiquitousKeyValueStore

  /// Creates a cloud storage instance backed by NSUbiquitousKeyValueStore.
  public init(store: NSUbiquitousKeyValueStore = .default) {
    self.store = store
  }

  /// Reads binary data from the iCloud key-value store.
  public func data(forKey defaultName: String) -> Data? {
    store.data(forKey: defaultName)
  }

  /// Sets or removes binary data in the iCloud key-value store.
  public func set(_ data: Data?, forKey defaultName: String) {
    if let data {
      store.set(data, forKey: defaultName)
    } else {
      store.removeObject(forKey: defaultName)
    }
  }

  /// Forces in-memory changes to synchronize with disk/iCloud daemon.
  public func synchronize() -> Bool {
    store.synchronize()
  }
}
