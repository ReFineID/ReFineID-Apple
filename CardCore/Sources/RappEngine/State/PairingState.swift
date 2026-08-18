// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Pairing component state.
///
/// A pairing instance exists per stored or in-progress peer relationship;
/// `unpaired` is the absence of one. Raw values are the formal model's names.
internal enum PairingState: String, CaseIterable, Sendable {
  case unpaired
  /// Requester only.
  case offerActive = "offer_active"
  case handshaking
  case confirming
  case pairedDisconnected = "paired_disconnected"
  case pairedConnected = "paired_connected"
  case revoked

  /// Whether a pairing record is stored in this state.
  ///
  /// An authenticated protocol violation revokes a stored pairing but only
  /// aborts an attempt that has not stored one.
  internal var holdsStoredPairing: Bool {
    switch self {
    case .pairedDisconnected, .pairedConnected: true
    case .unpaired, .offerActive, .handshaking, .confirming, .revoked: false
    }
  }
}
