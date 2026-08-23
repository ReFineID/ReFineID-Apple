// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_REMOTE_CARD
import CardCore

/// Classifies which connection events demand explicit user action before
/// the phone proxy reconnects.
internal enum PhoneRelayFailStops {
    /// Whether the event is a fail-stop that suspends automatic
    /// reconnection until the holder acts.
    internal static func requireExplicitUserAction(
        _ event: RappConnectionCoordinator.Event
    ) -> Bool {
        switch event {
        case .terminal(_, _, let reason):
            switch reason {
            case .credentialRejected, .cardCompletionAmbiguous:
                true

            case .userDenied, .requestExpired, .cancelled,
                 .requestInvalidOrUnsupported, .retryPolicyRefused,
                 .cardRemovedBeforeTransmit, nil:
                false
            }

        case .closed(let reason):
            switch reason {
            case .handshake(.protocolFailure), .handshake(.pairRevoked),
                 .operation(.protocolFailure), .operation(.pairRevoked):
                true

            case .handshake(.localRequest), .handshake(.transportClosed),
                 .operation(.localRequest), .operation(.transportClosed),
                 .operation(.terminalFrameReleased), .transportFailure,
                 .localRequest:
                false
            }

        case .established, .inspectPrerequisites, .awaitUserApproval,
             .executeSafeRead, .executeCardCommand, .completed,
             .advisoryCancellation, .operationFinished, .peerBusy,
             .peerUnknownOperation:
            false
        }
    }
}
#endif
