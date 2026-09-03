// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the specification registers them,
// so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// Credential profiles the registry admits.
internal enum ProfileName: String, CaseIterable, Equatable {
  case cardStatus = "fi.eid.card-status.v1"
  case authentication = "fi.eid.authentication.v1"
  case documentSigning = "fi.eid.document-signing.v1"
  case activation = "fi.eid.activation.v1"
  case pinManagement = "fi.eid.pin-management.v1"

  internal init?(rawValue: String) {
    switch rawValue {
    case "fi.eid.card-status.v1", "fi.refineid.card-status.v1":
      self = .cardStatus
    case "fi.eid.authentication.v1", "fi.refineid.authentication.v1":
      self = .authentication
    case "fi.eid.document-signing.v1", "fi.refineid.document-signing.v1":
      self = .documentSigning
    case "fi.eid.activation.v1", "fi.refineid.activation.v1":
      self = .activation
    case "fi.eid.pin-management.v1", "fi.refineid.pin-management.v1":
      self = .pinManagement
    default:
      return nil
    }
  }
}

// swiftlint:enable sorted_enum_cases
