// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

#if canImport(UIKit)
  import UIKit
#endif

/// Represents this device's persistent cryptographic identity for same-account RAPP pairing.
///
/// Private keys are generated locally in the device's Data Protection Keychain
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) and never leave this device.
public final class RappDeviceIdentity: @unchecked Sendable {
  // MARK: Public Types

  /// Storage or cryptographic failures when loading or creating device identities.
  public enum Failure: Error, Equatable, Sendable {
    case generationFailed
    case keychainFailure(OSStatus)
    case malformedKey
  }

  // MARK: Static Properties

  private static let keyByteCount = 32
  private static let lock = NSLock()

  #if os(iOS)
    private static let iPhoneModelTable: [String: String] = [
      "iPhone14,2": "iPhone 13 Pro",
      "iPhone14,3": "iPhone 13 Pro Max",
      "iPhone14,4": "iPhone 13 mini",
      "iPhone14,5": "iPhone 13",
      "iPhone14,6": "iPhone SE (3rd generation)",
      "iPhone14,7": "iPhone 14",
      "iPhone14,8": "iPhone 14 Plus",
      "iPhone15,2": "iPhone 14 Pro",
      "iPhone15,3": "iPhone 14 Pro Max",
      "iPhone15,4": "iPhone 15",
      "iPhone15,5": "iPhone 15 Plus",
      "iPhone16,1": "iPhone 15 Pro",
      "iPhone16,2": "iPhone 15 Pro Max",
      "iPhone17,1": "iPhone 16 Pro",
      "iPhone17,2": "iPhone 16 Pro Max",
      "iPhone17,3": "iPhone 16",
      "iPhone17,4": "iPhone 16 Plus",
      "x86_64": "iOS Simulator",
      "arm64": "iOS Simulator",
    ]
  #endif

  // MARK: Properties

  /// Unique stable identifier of this device.
  public let deviceID: UUID
  /// Human-readable device name.
  public let deviceName: String
  /// Hardware model identifier.
  public let modelName: String
  /// 32-byte Curve25519 static private key material.
  public let privateKeyData: Data
  /// 32-byte Curve25519 static public key material.
  public let publicKeyData: Data

  private let accessGroup: String?
  private let service: String

  // MARK: Initialization

  /// Loads or creates the persistent identity for this device.
  public convenience init(accessGroup: String? = nil) throws {
    try self.init(
      accessGroup: accessGroup,
      service: "fi.refineid.rapp.device-identity",
      deviceName: Self.resolveDeviceName(),
      modelName: Self.resolveModelName()
    )
  }

  /// Isolated initializer for testing with in-memory or custom service keys.
  public init(
    accessGroup: String?,
    service: String,
    deviceName: String,
    modelName: String,
    fixedPrivateKey: Data? = nil,
    fixedDeviceID: UUID? = nil
  ) throws {
    self.accessGroup = accessGroup
    self.service = service
    self.deviceName = deviceName
    self.modelName = modelName

    if let fixedPrivateKey, let fixedDeviceID {
      guard fixedPrivateKey.count == Self.keyByteCount else { throw Failure.malformedKey }
      let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: fixedPrivateKey)
      self.privateKeyData = key.rawRepresentation
      self.publicKeyData = key.publicKey.rawRepresentation
      self.deviceID = fixedDeviceID
      return
    }

    Self.lock.lock()
    defer { Self.lock.unlock() }

    // Load or generate UUID
    let loadedUUID = Self.loadOrCreateUUID(service: service, accessGroup: accessGroup)
    self.deviceID = loadedUUID

    // Load or generate Curve25519 key
    let loadedKey = Self.loadOrCreateKey(service: service, accessGroup: accessGroup)
    self.privateKeyData = loadedKey.rawRepresentation
    self.publicKeyData = loadedKey.publicKey.rawRepresentation
  }

  // MARK: Private Helpers

  private static func loadOrCreateUUID(service: String, accessGroup: String?) -> UUID {
    let account = "device_uuid"
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess,
      let data = result as? Data,
      let string = String(data: data, encoding: .utf8),
      let uuid = UUID(uuidString: string)
    {
      return uuid
    }

    let newUUID = UUID()
    let uuidData = Data(newUUID.uuidString.utf8)
    var addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: uuidData,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
    ]
    if let accessGroup {
      addQuery[kSecAttrAccessGroup as String] = accessGroup
    }

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus != errSecSuccess, addStatus != errSecDuplicateItem else {
      return newUUID
    }

    // Retry without access group if entitlement was rejected
    addQuery.removeValue(forKey: kSecAttrAccessGroup as String)
    _ = SecItemAdd(addQuery as CFDictionary, nil)
    return newUUID
  }

  private static func loadOrCreateKey(
    service: String,
    accessGroup: String?
  ) -> Curve25519.KeyAgreement.PrivateKey {
    let account = "device_static_private_key"
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data, data.count == Self.keyByteCount {
      if let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
        return key
      }
    }

    let newKey = Curve25519.KeyAgreement.PrivateKey()
    var addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: newKey.rawRepresentation,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
    ]
    if let accessGroup {
      addQuery[kSecAttrAccessGroup as String] = accessGroup
    }

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus != errSecSuccess, addStatus != errSecDuplicateItem else {
      return newKey
    }

    // Retry without access group if entitlement was rejected
    addQuery.removeValue(forKey: kSecAttrAccessGroup as String)
    _ = SecItemAdd(addQuery as CFDictionary, nil)
    return newKey
  }

  private static func resolveDeviceName() -> String {
    #if os(iOS)
      return UIDevice.current.name
    #elseif os(macOS)
      return Host.current().localizedName ?? "Mac"
    #else
      return "Apple Device"
    #endif
  }

  #if os(iOS)
    private static func friendlyIPhoneModelName(_ identifier: String) -> String {
      if let known = iPhoneModelTable[identifier] {
        return known
      }
      if identifier.hasPrefix("iPhone") {
        return identifier
      }
      return UIDevice.current.model
    }
  #endif

  private static func resolveModelName() -> String {
    #if os(iOS)
      var systemInfo = utsname()
      uname(&systemInfo)
      let machineMirror = Mirror(reflecting: systemInfo.machine)
      let rawIdentifier = machineMirror.children.reduce(into: "") { result, element in
        guard let value = element.value as? Int8, value != 0 else { return }
        result.append(Character(UnicodeScalar(UInt8(value))))
      }
      if !rawIdentifier.isEmpty {
        return friendlyIPhoneModelName(rawIdentifier)
      }
      return UIDevice.current.model
    #elseif os(macOS)
      var size = 0
      sysctlbyname("hw.model", nil, &size, nil, 0)
      if size > 0 {
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let bytes = model.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        let raw = String(bytes: bytes, encoding: .utf8) ?? "Mac"
        return friendlyMacModelName(raw)
      }
      return "Mac"
    #else
      return "Apple"
    #endif
  }

  private static func friendlyMacModelName(_ raw: String) -> String {
    if raw.hasPrefix("MacBookPro") { return "MacBook Pro" }
    if raw.hasPrefix("MacBookAir") { return "MacBook Air" }
    if raw.hasPrefix("MacBook") { return "MacBook" }
    if raw.hasPrefix("Macmini") { return "Mac mini" }
    if raw.hasPrefix("iMac") { return "iMac" }
    if raw.hasPrefix("MacStudio") { return "Mac Studio" }
    if raw.hasPrefix("MacPro") { return "Mac Pro" }
    if raw.hasPrefix("Mac") { return "Mac" }
    return raw
  }
}
