// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Absent and empty are different bytes on the wire, so the optionality is
// the protocol's own and not a convenience.
// swiftlint:disable discouraged_optional_collection

/// One transport a scanned offer advertises.
public struct RappOfferCandidate: Equatable, Sendable {
    /// The transport profile this candidate implements.
    public var profile: String
    /// The identifier naming this candidate within the offer.
    public var candidateId: String
    /// Present only for the stream profile, whose parameters carry endpoints.
    public var streamEndpoints: [String]?

    /// Describes one advertised transport.
    public init(profile: String, candidateId: String, streamEndpoints: [String]?) {
        self.profile = profile
        self.candidateId = candidateId
        self.streamEndpoints = streamEndpoints
    }
}

// swiftlint:enable discouraged_optional_collection
