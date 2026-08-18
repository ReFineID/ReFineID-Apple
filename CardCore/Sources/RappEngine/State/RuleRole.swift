// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The role a transition rule applies to.
internal enum RuleRole: String, CaseIterable, Sendable {
  case requester
  case proxy
  case both

  /// Whether an endpoint in `role` implements rules carrying this value.
  internal func includes(_ role: EndpointRole) -> Bool {
    switch self {
    case .both: true
    case .requester: role == .requester
    case .proxy: role == .proxy
    }
  }
}
