// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Which certificate a public read selects.
internal enum CertificateKind: String, CaseIterable, Equatable, Sendable {
    case authentication = "authentication"
    case signature = "signature"
}
