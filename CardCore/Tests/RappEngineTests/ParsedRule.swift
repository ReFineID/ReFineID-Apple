// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The model names this field `to`; these types mirror the document's rules
// verbatim so the comparison reads field for field.
// swiftlint:disable identifier_name

import Foundation

@testable import RappEngine

/// One rule as written in the formal model.
internal struct ParsedRule {
    internal var from: [String] = []
    internal var event = ""
    internal var role = ""
    internal var condition: String?
    internal var to = ""
    internal var actions: [String] = []
}

// swiftlint:enable identifier_name
