// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The endpoint's role in a pairing.
///
/// Every rule in the formal model names the role or roles that implement it,
/// so an endpoint runs exactly the projection belonging to it.
internal enum EndpointRole: String, CaseIterable, Sendable {
  case requester
  case proxy
}
