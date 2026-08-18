// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A condition a transition rule requires.
///
/// A failed guard on a rule triggered by an authenticated peer message
/// produces the bounded response named by the failure taxonomy and leaves
/// state unchanged. A failed guard on a local event is a no-op. Raw values are
/// the formal model's guard names.
internal enum RappGuard: String, CaseIterable, Sendable {
  case userInitiated = "user_initiated"
  case localUserAction = "local_user_action"
  case offerValidAndSupported = "offer_valid_and_supported"
  case offerLive = "offer_live"
  case transcriptMatches = "transcript_matches"
  case grantedSetsEqual = "granted_sets_equal"
  case pairingPaired = "pairing_paired"
  case initiationPermitted = "initiation_permitted"
  case readyParametersMatch = "ready_parameters_match"
  case deadlineNotExpired = "deadline_not_expired"
  case anotherSessionLive = "another_session_live"
  case admissionPermitted = "admission_permitted"
  case hashEchoMatches = "hash_echo_matches"
  case hashMatches = "hash_matches"
  case zeroTransmissions = "zero_transmissions"
  case provenNoTransmission = "proven_no_transmission"
  case profileHasNoConsequentialCommand = "profile_has_no_consequential_command"
}
