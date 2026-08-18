// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The transition tables of the formal RAPP state model, transcribed in model
/// order so a rule here and a rule there can be compared line for line.
internal enum RappModelTables {
  /// Pairing component rules.
  internal static let pairing: [RappRule<PairingState, PairingEvent>] = [
    RappRule(
      from: .unpaired,
      event: .createOffer,
      role: .requester,
      condition: .userInitiated,
      to: .offerActive,
      actions: [.generateOfferId, .generatePairingSecret, .startOfferExpiry, .displayQr]
    ),
    RappRule(
      from: .unpaired,
      event: .offerScanned,
      role: .proxy,
      condition: .offerValidAndSupported,
      to: .handshaking,
      actions: [.selectOneCandidate, .connectCandidate, .preparePairingResponder]
    ),
    RappRule(
      from: .offerActive,
      event: .candidateConnected,
      role: .requester,
      condition: .offerLive,
      to: .handshaking,
      actions: [.beginPairingHandshakeInitiator]
    ),
    RappRule(
      from: .offerActive,
      event: .offerExpiredOrCancelled,
      role: .requester,
      to: .unpaired,
      actions: [.destroyPairingSecret, .invalidateOffer, .hideQr]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeAuthenticated,
      role: .both,
      condition: .transcriptMatches,
      to: .confirming,
      actions: [
        .deriveChannelIdentifiers, .destroyPairingSecret, .stopAcceptingCandidates, .hideQr,
        .sendPairingHello, .showPeerAndRequestedGrants,
      ]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeFailed,
      role: .requester,
      to: .offerActive,
      actions: [.discardCandidate, .retainOffer]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeFailed,
      role: .proxy,
      to: .unpaired,
      actions: [.discardCandidate]
    ),
    RappRule(
      from: .handshaking,
      event: .offerExpiredOrCancelled,
      role: .requester,
      to: .unpaired,
      actions: [.destroyPairingSecret, .invalidateOffer, .closeCandidate]
    ),
    RappRule(
      from: .confirming,
      event: .bothUsersConfirmed,
      role: .both,
      condition: .grantedSetsEqual,
      to: .pairedDisconnected,
      actions: [.storePairRecordAtomically, .invalidateOffer, .closePairingChannel]
    ),
    RappRule(
      from: .confirming,
      event: .deniedAbortedOrTimedOut,
      role: .both,
      to: .unpaired,
      actions: [
        .sendPairingAbortBestEffort, .destroyCandidateKeys, .invalidateOffer, .closeCandidate,
      ]
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .sessionHealthy,
      role: .both,
      to: .pairedConnected,
      actions: [.showConnected]
    ),
    RappRule(
      from: .pairedConnected,
      event: .sessionClosed,
      role: .both,
      to: .pairedDisconnected,
      actions: [.showPairedDisconnected]
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .forgetPairing,
      role: .both,
      condition: .localUserAction,
      to: .unpaired,
      actions: [.destroyPairKeys, .destroyRelayTokens, .clearPairMetadata]
    ),
    RappRule(
      from: .pairedConnected,
      event: .forgetPairing,
      role: .both,
      condition: .localUserAction,
      to: .unpaired,
      actions: [.closeSession, .destroyPairKeys, .destroyRelayTokens, .clearPairMetadata]
    ),
    RappRule(
      from: .pairedConnected,
      event: .authenticatedProtocolViolation,
      role: .both,
      to: .revoked,
      actions: [.sendCloseBestEffort, .closeSession, .destroyPairKeys, .showRevoked]
    ),
    RappRule(
      from: .pairedConnected,
      event: .localRevoke,
      role: .both,
      condition: .localUserAction,
      to: .revoked,
      actions: [.sendCloseBestEffort, .closeSession, .destroyPairKeys, .showRevoked]
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .localRevoke,
      role: .both,
      condition: .localUserAction,
      to: .revoked,
      actions: [.destroyPairKeys, .showRevoked]
    ),
    RappRule(
      from: .pairedConnected,
      event: .peerRevocationNotice,
      role: .both,
      to: .revoked,
      actions: [.recordPeerInitiated, .closeSession, .destroyPairKeys, .showRevoked]
    ),
    RappRule(
      from: .revoked,
      event: .forgetPairing,
      role: .both,
      condition: .localUserAction,
      to: .unpaired,
      actions: [.clearResidualPairRecord]
    ),
  ]
}
