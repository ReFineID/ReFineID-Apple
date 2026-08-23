// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The model names this field `to`; these types mirror the document's rules
// verbatim so the comparison reads field for field.

import Foundation

@testable import RappEngine

/// A single (machine, from, event, role) rule with its outcome, expanded so a
/// list-valued `from` and a `both` role become one entry each.
internal struct ModelEntry: Hashable, Comparable {
  internal let machine: String
  internal let from: String
  internal let event: String
  internal let role: String
  internal let to: String
  internal let actions: String

  internal var label: String { "\(machine) \(from) / \(event) / \(role)" }

  internal static func < (lhs: Self, rhs: Self) -> Bool { lhs.label < rhs.label }
}
