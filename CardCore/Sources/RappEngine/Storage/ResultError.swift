// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Stable failure name accompanying a non-successful result.
internal enum ResultError: String, Equatable {
  case userDenied = "user_denied"
  case requestExpired = "request_expired"
  case cancelled
  case requestInvalidOrUnsupported = "request_invalid_or_unsupported"
  case retryPolicyRefused = "retry_policy_refused"
  case credentialRejected = "credential_rejected"
  case cardRemovedBeforeTransmit = "card_removed_before_transmit"
  case cardCompletionAmbiguous = "card_completion_ambiguous"
}
