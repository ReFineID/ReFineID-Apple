// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

extension PrimeStore {
  /// Every decodable prime, including the short-lived staged record.
  internal static func storedItems() -> [StoredItem] {
    if TestCredentialEnvironment.isTestMode {
      return TestCredentialEnvironment.allPrimes().compactMap { account, data in
        guard let identity = try? JSONDecoder().decode(PrimedIdentity.self, from: data) else {
          return nil
        }
        return StoredItem(account: account, identity: identity)
      }
    }
    var search: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if KeychainPlatform.usesDataProtection {
      search[kSecUseDataProtectionKeychain as String] = true
      search[kSecAttrSynchronizable as String] = false
      search[kSecReturnData as String] = true
    }
    search[kSecMatchLimit as String] = kSecMatchLimitAll
    search[kSecReturnAttributes as String] = true
    var items: CFTypeRef?
    guard SecItemCopyMatching(search as CFDictionary, &items) == errSecSuccess,
      let found = items as? [[String: Any]]
    else {
      return []
    }
    return found.compactMap { (attributes: [String: Any]) -> StoredItem? in
      guard let account = attributes[kSecAttrAccount as String] as? String else {
        return nil
      }
      if let data = attributes[kSecValueData as String] as? Data,
        let identity = try? JSONDecoder().decode(PrimedIdentity.self, from: data)
      {
        return StoredItem(account: account, identity: identity)
      }
      if let identity = read(account: account) {
        return StoredItem(account: account, identity: identity)
      }
      return nil
    }
  }

  /// Item coordinates shared by every operation on one card's prime.
  ///
  /// The accessibility attribute is deliberately absent here: it belongs
  /// on the write, and a search that filters on it would miss items
  /// written under any other policy instead of replacing them.
  internal static func query(account: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if KeychainPlatform.usesDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
      query[kSecAttrSynchronizable as String] = false
    }
    return query
  }

  /// Removes one account without exposing its coordinates to callers.
  internal static func delete(account: String) {
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.deletePrime(account: account)
      return
    }
    SecItemDelete(query(account: account) as CFDictionary)
  }
}
