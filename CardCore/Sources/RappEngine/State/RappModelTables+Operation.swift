// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension RappModelTables {
  /// Operation component rules.
  ///
  /// Messages naming an unknown or terminal operation are stale-reference
  /// races and appear in no rule; they transition nothing.
  internal static let operation: [RappRule<OperationState, OperationEvent>] = [
    RappRule(
      from: .none,
      event: .requestSent,
      role: .requester,
      condition: .admissionPermitted,
      to: .requested,
      actions: [.computeRequestHash, .journalRequest, .startExpiryClock]
    ),
    RappRule(
      from: .none,
      event: .requestReceived,
      role: .proxy,
      condition: .admissionPermitted,
      to: .requested,
      actions: [.validateSchemaHashExpiryAndContext, .startExpiryClock]
    ),
    RappRule(
      from: .requested,
      event: .requestValid,
      role: .proxy,
      to: .awaitingConsent,
      actions: [.beginSafePrerequisiteReads, .presentConsentPerProfile]
    ),
    RappRule(
      from: .requested,
      event: .requestInvalidOrUnsupported,
      role: .proxy,
      to: .rejected,
      actions: [.sendResultRejected]
    ),
    RappRule(
      from: [.requested, .awaitingConsent],
      event: .cancelReceived,
      role: .proxy,
      to: .cancelled,
      actions: [.clearOperationCredentials, .dismissConsent, .sendResultCancelled]
    ),
    RappRule(
      from: [.requested, .awaitingConsent],
      event: .requestExpired,
      role: .proxy,
      to: .cancelled,
      actions: [.clearOperationCredentials, .dismissConsent, .sendResultCancelled]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .userDenied,
      role: .proxy,
      to: .denied,
      actions: [.clearOperationCredentials, .sendResultDenied]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .retryPolicyRefused,
      role: .proxy,
      to: .rejected,
      actions: [
        .clearOperationCredentials, .sendResultRetryPolicyRefused, .requestSessionClose,
      ]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .invalidCanOrPin1OrPin2,
      role: .proxy,
      to: .credentialRejected,
      actions: [
        .clearAllActiveCredentials, .removeRejectedCredentialAndDerivedState,
        .sendResultCredentialRejectedBestEffort, .revokePairAfterCredentialRejection,
        .requestSessionCloseCredentialRejected,
      ]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .safeReadsComplete,
      role: .proxy,
      condition: .profileHasNoConsequentialCommand,
      to: .resultPending,
      actions: [.persistResult, .sendResultCompleted]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .userApprovedAndProxyReady,
      role: .proxy,
      condition: .zeroTransmissions,
      to: .prepared,
      actions: [.sendPrepared]
    ),
    RappRule(
      from: .prepared,
      event: .cancelReceived,
      role: .proxy,
      to: .cancelled,
      actions: [.clearOperationCredentials, .sendResultCancelled]
    ),
    RappRule(
      from: .prepared,
      event: .requestExpired,
      role: .proxy,
      to: .cancelled,
      actions: [.clearOperationCredentials, .sendResultCancelled]
    ),
    RappRule(
      from: .prepared,
      event: .validCommit,
      role: .proxy,
      condition: .hashMatches,
      to: .committed,
      actions: [.durablyWriteCommitBeforeTransmission]
    ),
    RappRule(
      from: .committed,
      event: .beginCardCommand,
      role: .proxy,
      condition: .zeroTransmissions,
      to: .executing,
      actions: [.consumeNonClonableCommand, .incrementTransmissionCountOnce]
    ),
    RappRule(
      from: .committed,
      event: .cancelReceived,
      role: .proxy,
      condition: .provenNoTransmission,
      to: .cancelled,
      actions: [.persistCancelled, .clearOperationCredentials, .sendResultCancelled]
    ),
    RappRule(
      from: [.committed, .executing],
      event: .crashRecoveredWithoutTerminalResult,
      role: .both,
      to: .ambiguous,
      actions: [.persistAmbiguous, .prohibitRetry]
    ),
    RappRule(
      from: .executing,
      event: .cardSuccess,
      role: .proxy,
      to: .resultPending,
      actions: [.persistResult, .clearOperationCredentials, .sendResultCompleted]
    ),
    RappRule(
      from: .executing,
      event: .invalidCanOrPin1OrPin2,
      role: .proxy,
      to: .credentialRejected,
      actions: [
        .clearAllActiveCredentials, .removeRejectedCredentialAndDerivedState,
        .sendResultCredentialRejectedBestEffort, .revokePairAfterCredentialRejection,
        .requestSessionCloseCredentialRejected,
      ]
    ),
    RappRule(
      from: .executing,
      event: .cardPolicyRejection,
      role: .proxy,
      to: .rejected,
      actions: [.clearOperationCredentials, .persistRejection, .sendResultRejected]
    ),
    RappRule(
      from: .executing,
      event: .cardRemovedBeforeTransmit,
      role: .proxy,
      condition: .provenNoTransmission,
      to: .cancelled,
      actions: [.persistCancelled, .clearOperationCredentials, .sendResultCancelled]
    ),
    RappRule(
      from: .executing,
      event: .cardRemovedOrTransportUncertain,
      role: .proxy,
      to: .ambiguous,
      actions: [
        .clearOperationCredentials, .persistAmbiguous, .prohibitRetry,
        .sendResultAmbiguousBestEffort, .requestSessionCloseAmbiguous,
      ]
    ),
    RappRule(
      from: .executing,
      event: .cancelReceived,
      role: .proxy,
      to: .executing,
      actions: [.recordAdvisoryCancel]
    ),
    RappRule(
      from: .executing,
      event: .sessionClosedPostCommit,
      role: .proxy,
      to: .executing,
      actions: [.continueCardExchangeLocally, .noteResultDeliveryImpossible]
    ),
    RappRule(
      from: .resultPending,
      event: .validResultAck,
      role: .proxy,
      to: .completed,
      actions: [.persistCompleted, .releaseResult]
    ),
    RappRule(
      from: .resultPending,
      event: .sessionClosedBeforeAck,
      role: .proxy,
      to: .deliveryUncertain,
      actions: [.persistDeliveryUncertain, .prohibitCardRetry, .retainResultUnderLocalStorage]
    ),
    RappRule(
      from: .committed,
      event: .sessionClosedPostCommit,
      role: .proxy,
      to: .cancelled,
      actions: [.persistCancelled, .clearOperationCredentials]
    ),
    RappRule(
      from: .requested,
      event: .preparedReceived,
      role: .requester,
      condition: .hashEchoMatches,
      to: .prepared,
      actions: [.journalPrepared]
    ),
    RappRule(
      from: [.requested, .prepared],
      event: .cancelSentOrRequestExpired,
      role: .requester,
      to: .cancelled,
      actions: [.sendOperationCancel, .journalCancelled]
    ),
    RappRule(
      from: .prepared,
      event: .commitSent,
      role: .requester,
      to: .committed,
      actions: [.journalCommitIntentDurably]
    ),
    RappRule(
      from: .requested,
      event: .resultCompletedReceived,
      role: .requester,
      condition: .profileHasNoConsequentialCommand,
      to: .completed,
      actions: [.sendResultAck, .journalCompleted]
    ),
    RappRule(
      from: [.requested, .prepared],
      event: .resultDeniedReceived,
      role: .requester,
      to: .denied,
      actions: [.journalDenied]
    ),
    RappRule(
      from: [.requested, .prepared, .committed],
      event: .resultCancelledReceived,
      role: .requester,
      to: .cancelled,
      actions: [.journalCancelled]
    ),
    RappRule(
      from: [.requested, .prepared, .committed],
      event: .resultRejectedReceived,
      role: .requester,
      to: .rejected,
      actions: [.journalRejected]
    ),
    RappRule(
      from: [.requested, .prepared, .committed],
      event: .resultCredentialRejectedReceived,
      role: .requester,
      to: .credentialRejected,
      actions: [.journalCredentialRejected, .revokePairAfterCredentialRejection]
    ),
    RappRule(
      from: .committed,
      event: .resultCompletedReceived,
      role: .requester,
      to: .completed,
      actions: [.sendResultAck, .journalCompleted]
    ),
    RappRule(
      from: .committed,
      event: .resultAmbiguousReceived,
      role: .requester,
      to: .ambiguous,
      actions: [.journalAmbiguous, .prohibitRetry]
    ),
    RappRule(
      from: .committed,
      event: .sessionClosedPostCommit,
      role: .requester,
      to: .ambiguous,
      actions: [.journalAmbiguous, .prohibitRetry]
    ),
    RappRule(
      from: [.requested, .awaitingConsent, .prepared],
      event: .sessionClosedPreCommit,
      role: .both,
      to: .cancelled,
      actions: [.clearOperationCredentials, .persistCancelled]
    ),
  ]
}
