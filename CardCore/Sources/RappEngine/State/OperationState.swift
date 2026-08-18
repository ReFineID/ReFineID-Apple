// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Operation component state.
///
/// An operation instance exists per operation identifier. Terminal states are
/// permanent journal records that accept no further transitions.
internal enum OperationState: String, CaseIterable, Sendable {
  case none
  case requested
  /// Proxy only.
  case awaitingConsent = "awaiting_consent"
  case prepared
  case committed
  /// Proxy only.
  case executing
  /// Proxy only.
  case resultPending = "result_pending"
  case completed
  case denied
  case cancelled
  case rejected
  case credentialRejected = "credential_rejected"
  case ambiguous
  case deliveryUncertain = "delivery_uncertain"

  /// Whether this state is a permanent journal record.
  internal var isTerminal: Bool {
    switch self {
    case .completed, .denied, .cancelled, .rejected, .credentialRejected,
      .ambiguous, .deliveryUncertain:
      true
    case .none, .requested, .awaitingConsent, .prepared, .committed, .executing,
      .resultPending:
      false
    }
  }

  /// Whether the instance occupies the single active-operation slot.
  internal var isActive: Bool {
    self != .none && !isTerminal
  }
}
