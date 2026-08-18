// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The slim relay's channel, carried by the pairing's own Noise session.
  ///
  /// This is the whole of what binds a request to the pairing: the session
  /// was established from the stored pair record, so a frame that opens came
  /// from the paired device and no other. Nothing above it needs to say so
  /// again.
  public struct SignRelayNoiseChannel: SignRelayChannel {
    private let session: RappSessionBridge

    /// Carries the relay over `session`, which must already be established.
    public init(session: RappSessionBridge) {
      self.session = session
    }

    /// Seals the payload over the pairing's session.
    public func seal(_ payload: Data) throws -> Data {
      try session.sealPayload(payload)
    }

    /// Opens the frame, ending the session if it will not open.
    public func open(_ frame: Data) throws -> Data {
      try session.openPayload(frame)
    }
  }
#endif
