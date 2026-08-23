// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension RappModelTables {
    /// Session component rules.
    internal static let session: [RappRule<SessionState, SessionEvent>] = [
        RappRule(
            from: .absent,
            event: .connect,
            role: .requester,
            condition: .initiationPermitted,
            to: .connecting,
            actions: [.selectOneTransport, .openTransport]
        ),
        RappRule(
            from: .absent,
            event: .transportAccepted,
            role: .proxy,
            condition: .pairingPaired,
            to: .authenticating,
            actions: [.associatePairingFromRendezvous, .beginKkResponder]
        ),
        RappRule(
            from: .connecting,
            event: .transportConnected,
            role: .requester,
            to: .authenticating,
            actions: [.beginKkInitiator]
        ),
        RappRule(
            from: .connecting,
            event: .transportFailed,
            role: .requester,
            to: .closed,
            actions: [.destroySessionMaterial, .showConnectionStopped]
        ),
        RappRule(
            from: .connecting,
            event: .userDisconnect,
            role: .requester,
            to: .closed,
            actions: [.abortCandidate, .destroySessionMaterial, .showConnectionStopped]
        ),
        RappRule(
            from: .authenticating,
            event: .handshakeComplete,
            role: .both,
            to: .authenticating,
            actions: [.deriveSessionIdentifiers, .sendSessionReady]
        ),
        RappRule(
            from: .authenticating,
            event: .secondSessionDetected,
            role: .proxy,
            condition: .anotherSessionLive,
            to: .closed,
            actions: [.sendErrorBusy, .destroySessionMaterial, .closeCandidate]
        ),
        RappRule(
            from: .authenticating,
            event: .readyVerified,
            role: .both,
            condition: .readyParametersMatch,
            to: .healthy,
            actions: [.startAuthenticatedLiveness, .showConnected]
        ),
        RappRule(
            from: .authenticating,
            event: .candidateFailure,
            role: .both,
            to: .closed,
            actions: [
                .destroySessionMaterial, .closeCandidate, .countCandidateFailureHint,
                .showConnectionStopped
            ]
        ),
        RappRule(
            from: .authenticating,
            event: .busyReceived,
            role: .requester,
            to: .closed,
            actions: [.destroySessionMaterial, .closeCandidate, .showConnectionStopped]
        ),
        RappRule(
            from: .authenticating,
            event: .peerCloseReceived,
            role: .both,
            to: .closed,
            actions: [
                .recordPeerCloseReason, .destroySessionMaterial, .closeCandidate, .showConnectionStopped
            ]
        ),
        RappRule(
            from: .authenticating,
            event: .transportFailed,
            role: .both,
            to: .closed,
            actions: [.destroySessionMaterial, .showConnectionStopped]
        ),
        RappRule(
            from: .authenticating,
            event: .authenticatedProtocolViolation,
            role: .both,
            to: .closing,
            actions: [.sendCloseBestEffort, .showDisconnecting]
        ),
        RappRule(
            from: .healthy,
            event: .livenessMissed,
            role: .both,
            to: .checking,
            actions: [.blockNewOperations, .startBackoffAndDeadline, .showChecking]
        ),
        RappRule(
            from: .checking,
            event: .livenessRestored,
            role: .both,
            condition: .deadlineNotExpired,
            to: .healthy,
            actions: [.resetBackoff, .showConnected]
        ),
        RappRule(
            from: .checking,
            event: .livenessDeadlineExpired,
            role: .both,
            to: .closing,
            actions: [.showDisconnecting]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .userDisconnect,
            role: .both,
            to: .closing,
            actions: [.sendCloseBestEffort, .showDisconnecting]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .localCloseRequested,
            role: .both,
            to: .closing,
            actions: [.sendCloseBestEffort, .showDisconnecting]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .peerCloseReceived,
            role: .both,
            to: .closing,
            actions: [.recordPeerCloseReason, .showDisconnecting]
        ),
        RappRule(
            from: .closing,
            event: .peerCloseReceived,
            role: .both,
            to: .closing,
            actions: []
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .credentialRejected,
            role: .proxy,
            to: .closing,
            actions: [.destroyPairKeys, .showRevoked, .sendCloseBestEffort, .showDisconnecting]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .cardCompletionAmbiguous,
            role: .proxy,
            to: .closing,
            actions: [.showDisconnecting]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .transportFailed,
            role: .both,
            to: .closing,
            actions: [.noteCloseNoticeImpossible, .showDisconnecting]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .sessionIntegrityFailed,
            role: .both,
            to: .closing,
            actions: [.noteCloseNoticeImpossible, .showDisconnecting]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .authenticatedProtocolViolation,
            role: .both,
            to: .closing,
            actions: [.sendCloseBestEffort, .showDisconnecting]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .closeRequestedByPairing,
            role: .both,
            to: .closing,
            actions: [.showDisconnecting]
        ),
        RappRule(
            from: [.connecting, .authenticating],
            event: .closeRequestedByPairing,
            role: .both,
            to: .closed,
            actions: [.destroySessionMaterial, .closeCandidate, .showConnectionStopped]
        ),
        RappRule(
            from: [.healthy, .checking],
            event: .localSecurityShutdown,
            role: .both,
            to: .closing,
            actions: [.noteCloseNoticeImpossible, .showDisconnecting]
        ),
        RappRule(
            from: [.connecting, .authenticating],
            event: .localSecurityShutdown,
            role: .both,
            to: .closed,
            actions: [.destroySessionMaterial, .showConnectionStopped]
        ),
        RappRule(
            from: .closing,
            event: .transportFailed,
            role: .both,
            to: .closing,
            actions: [.proceedWithoutCloseNotice]
        ),
        RappRule(
            from: .closing,
            event: .closeCompleteOrDeadline,
            role: .both,
            to: .closed,
            actions: [
                .destroySessionMaterial, .destroyCredentialBuffers, .persistTerminalSessionRecord,
                .showConnectionStopped
            ]
        )
    ]
}
