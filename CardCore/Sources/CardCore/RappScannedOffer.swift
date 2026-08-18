// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  /// Reads a scanned one-use pairing offer without consuming it.
  public enum RappScannedOffer {
    /// One transport candidate carried by a scanned pairing offer.
    public struct Candidate: Sendable, Equatable {
      /// Registered transport profile name.
      public let profile: String
      /// Requester-chosen candidate identifier.
      public let candidateID: String
      /// Decoded stream listener endpoints; empty on other profiles.
      public let streamEndpoints: [String]

      /// Creates a candidate from already-decoded offer facts.
      public init(profile: String, candidateID: String, streamEndpoints: [String]) {
        self.profile = profile
        self.candidateID = candidateID
        self.streamEndpoints = streamEndpoints
      }
    }

    /// Lists the offer's transport candidates for local selection.
    ///
    /// The decoding bridge is cancelled before returning; the QR bearer
    /// secret does not outlive the call.
    public static func candidates(
      scannedOfferURI: String,
      clock: RappPlatformClock = RappPlatformClock()
    ) throws -> [Candidate] {
      let bridge = try RappPairingBridge.fromScannedOffer(
        uri: scannedOfferURI,
        startedAtMonotonicMs: clock.monotonicMilliseconds()
      )
      defer { try? bridge.cancelPairing() }
      return try bridge.offerCandidates().map { candidate in
        Candidate(
          profile: candidate.profile,
          candidateID: candidate.candidateId,
          streamEndpoints: candidate.streamEndpoints ?? []
        )
      }
    }
  }
#endif
