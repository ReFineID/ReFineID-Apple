// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@Suite("RAPP shipping configuration")
struct RappShippingConfigurationTests {
  private static let classID = "fi.refineid.ReFineID.rapp-token"
  private static let service = "_refineid-rly._tcp"

  @Test("RAPP and smart-card drivers have separate CryptoTokenKit classes")
  func separateTokenDrivers() throws {
    #expect(PersistentTokenIdentity.classID == Self.classID)

    let reader = try Self.plist("Config/TokenExtension-Info.plist")
    let rapp = try Self.plist("Config/RappTokenExtension-Info.plist")
    let readerAttributes = try #require(Self.extensionAttributes(reader))
    let rappAttributes = try #require(Self.extensionAttributes(rapp))
    #expect(readerAttributes["com.apple.ctk.class-id"] as? String == "fi.refineid.ReFineID.token")
    #expect(
      readerAttributes["com.apple.ctk.driver-class"] as? String
        == "ReFineIDTokenExtension.TokenDriver")
    #expect(readerAttributes["com.apple.ctk.token-type"] as? String == "smartcard")
    #expect(rappAttributes["com.apple.ctk.class-id"] as? String == Self.classID)
    #expect(
      rappAttributes["com.apple.ctk.driver-class"] as? String
        == "$(PRODUCT_MODULE_NAME).PersistentTokenDriver")
    #expect(rappAttributes["com.apple.ctk.token-type"] == nil)
  }

  @Test("RAPP extension is a distinct embedded product on every platform")
  func separateRappExtensionTarget() throws {
    let project = try String(
      contentsOf: Self.root.appending(path: "ReFineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    #expect(project.contains("ReFineIDRappTokenExtension"))
    #expect(project.contains(Self.classID))
    #expect(project.contains("RappTokenExtension"))
    #expect(project.contains("Config/RappTokenExtension-iOS.entitlements"))
    #expect(!project.contains("ReFineIDRappTokenExtension.appex */; platformFilters"))
  }

  @Test("RAPP network declarations are present in shipping containers")
  func networkDeclarations() throws {
    for path in [
      "Config/ReFineID-Info.plist",
      "Config/ReFineID-iOS-Info.plist",
      "Config/RappTokenExtension-Info.plist",
    ] {
      let plist = try Self.plist(path)
      #expect(plist["NSLocalNetworkUsageDescription"] is String)
      let services = try #require(plist["NSBonjourServices"] as? [String])
      #expect(services.contains(Self.service))
    }

    let rappIOS = try Self.plist("Config/RappTokenExtension-iOS.entitlements")
    #expect(rappIOS["keychain-access-groups"] is [Any])
    #expect(rappIOS["com.apple.security.smartcard"] == nil)
    #expect(rappIOS["com.apple.security.network.client"] == nil)

    for path in ["Config/ReFineID.entitlements", "Config/RappTokenExtension.entitlements"] {
      let entitlements = try Self.plist(path)
      #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
      #expect(entitlements["com.apple.security.network.server"] as? Bool == true)
    }

    let reader = try Self.plist("Config/TokenExtension.entitlements")
    #expect(reader["com.apple.security.smartcard"] as? Bool == true)
    #expect(reader["com.apple.security.network.client"] == nil)
    #expect(reader["com.apple.security.network.server"] == nil)

    let rapp = try Self.plist("Config/RappTokenExtension.entitlements")
    #expect(rapp["com.apple.security.smartcard"] == nil)
  }

  @Test("Release inspection enforces the separate RAPP archive topology")
  func releaseInspectionTopology() throws {
    let source = try String(
      contentsOf: Self.root.appending(
        path: "Scripts/apple-app-store-connect-release-manager.swift"),
      encoding: .utf8)
    #expect(source.contains("ReFineIDRappTokenExtension.appex"))
    #expect(source.contains("fi.refineid.ReFineID.rapp-token"))
    #expect(source.contains("RAPP and direct-reader entitlements are separated"))
    #expect(!source.contains("network entitlements match the gated-relay shape"))
  }

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func plist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appending(path: path))
    return try #require(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any])
  }

  private static func extensionAttributes(
    _ plist: [String: Any]
  ) -> [String: Any]? {
    (plist["NSExtension"] as? [String: Any])?["NSExtensionAttributes"]
      as? [String: Any]
  }
}
