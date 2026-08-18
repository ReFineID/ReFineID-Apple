// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Proxy's answer to a durable status query.
internal struct StatusReport: Equatable {
  internal var operationIdentifier: Data
  internal var known: Bool
  internal var state: OperationState?
  internal var requestHash: Data?

  internal init(
    operationIdentifier: Data, known: Bool, state: OperationState? = nil, requestHash: Data? = nil
  ) {
    self.operationIdentifier = operationIdentifier
    self.known = known
    self.state = state
    self.requestHash = requestHash
  }
}
