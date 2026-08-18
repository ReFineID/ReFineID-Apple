// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CoreImage
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
  import UIKit
  import VisionKit
#elseif os(macOS)
  import AppKit
#endif

internal enum RappApplePeerProfile {
  static let name = "apple-peer-v1"
  static let candidateID = "apple-peer-v1.nearby"

  /// Deterministic CBOR for an empty map.
  ///
  /// Apple peer discovery currently needs no public parameter beyond
  /// its bound profile and candidate ID.
  private static let emptyMapInitialByte: UInt8 = 0b1010_0000
  static let candidateParameters = Data([emptyMapInitialByte])

  /// Only profiles implemented end to end by the current phone executor.
  static let supportedCredentialProfiles = [
    "fi.eid.card-status.v1",
    "fi.eid.authentication.v1",
    "fi.eid.document-signing.v1",
  ]

  static func isSupported(_ profile: String) -> Bool {
    supportedCredentialProfiles.contains(profile)
  }

  static func label(for profile: String) -> String {
    switch profile {
    case "fi.eid.card-status.v1":
      String(localized: "Card status")
    case "fi.eid.authentication.v1":
      String(localized: "Browser authentication")
    case "fi.eid.document-signing.v1":
      String(localized: "Document signing")
    case "fi.eid.activation.v1":
      String(localized: "Card activation")
    case "fi.eid.pin-management.v1":
      String(localized: "PIN management")
    default:
      String(localized: "Unknown access")
    }
  }
}
