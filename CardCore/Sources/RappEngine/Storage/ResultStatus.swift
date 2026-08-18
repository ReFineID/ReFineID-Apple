// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Stable result state of an operation.
internal enum ResultStatus: String, Equatable {
  case completed
  case denied
  case cancelled
  case rejected
  case credentialRejected = "credential_rejected"
  case ambiguous
}
