// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import RappEngine

  /// Why a requester operation ended without a response.
  public enum RappRequesterClientError: Error, Sendable, Equatable {
    case noActivePair
    case noSelectedPair
    case protocolFailure
    case terminal(RappOperationDriver.TerminalReason?)
    case timedOut
    case transport
    case unexpectedResult
  }
#endif
