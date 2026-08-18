// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Typed output of one completed card operation.
internal enum CardOperationResult: Equatable {
  case inspection(CardInspection)
  case identity(displayName: String, personIdentifier: String)
  case certificate(Data)
  case signature(Data)
}
