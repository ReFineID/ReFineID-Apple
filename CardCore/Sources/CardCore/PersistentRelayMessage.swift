// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One correlated request or response on the encrypted local relay.
///
/// The document key for the correlation UUID is `id`; the Swift label is
/// `requestID`.
public enum PersistentRelayMessage: Codable, Equatable, Sendable {
  case failure(requestID: UUID, reason: PersistentRelayFailure)
  case identityRequest(requestID: UUID)
  case identityResponse(requestID: UUID, certificateDER: Data)
  case signatureRequest(
    requestID: UUID,
    profile: PersistentRelayCardProfile,
    algorithm: PersistentRelaySigningAlgorithm,
    digest: Data
  )
  case signatureResponse(requestID: UUID, signature: Data)

  private enum CaseKey: String, CodingKey {
    case failure = "failure"
    case identityRequest = "identityRequest"
    case identityResponse = "identityResponse"
    case signatureRequest = "signatureRequest"
    case signatureResponse = "signatureResponse"
  }

  private enum PayloadKey: String, CodingKey {
    case algorithm = "algorithm"
    case certificateDER = "certificateDER"
    case digest = "digest"
    case profile = "profile"
    case reason = "reason"
    case requestID = "id"
    case signature = "signature"
  }

  /// The correlation UUID shared by a request and its answer.
  public var requestID: UUID {
    switch self {
    case .identityRequest(let requestID), .identityResponse(let requestID, _),
      .signatureRequest(let requestID, _, _, _), .signatureResponse(let requestID, _),
      .failure(let requestID, _):
      requestID
    }
  }

  /// Decodes a relay message from the document form that names the
  /// correlation UUID `id`.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CaseKey.self)
    if container.contains(.failure) {
      let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .failure)
      self = .failure(
        requestID: try payload.decode(UUID.self, forKey: .requestID),
        reason: try payload.decode(PersistentRelayFailure.self, forKey: .reason)
      )
      return
    }
    if container.contains(.identityRequest) {
      let payload = try container.nestedContainer(
        keyedBy: PayloadKey.self, forKey: .identityRequest)
      self = .identityRequest(
        requestID: try payload.decode(UUID.self, forKey: .requestID)
      )
      return
    }
    if container.contains(.identityResponse) {
      let payload = try container.nestedContainer(
        keyedBy: PayloadKey.self, forKey: .identityResponse)
      self = .identityResponse(
        requestID: try payload.decode(UUID.self, forKey: .requestID),
        certificateDER: try payload.decode(Data.self, forKey: .certificateDER)
      )
      return
    }
    if container.contains(.signatureRequest) {
      let payload = try container.nestedContainer(
        keyedBy: PayloadKey.self, forKey: .signatureRequest)
      self = .signatureRequest(
        requestID: try payload.decode(UUID.self, forKey: .requestID),
        profile: try payload.decode(PersistentRelayCardProfile.self, forKey: .profile),
        algorithm: try payload.decode(PersistentRelaySigningAlgorithm.self, forKey: .algorithm),
        digest: try payload.decode(Data.self, forKey: .digest)
      )
      return
    }
    if container.contains(.signatureResponse) {
      let payload = try container.nestedContainer(
        keyedBy: PayloadKey.self, forKey: .signatureResponse)
      self = .signatureResponse(
        requestID: try payload.decode(UUID.self, forKey: .requestID),
        signature: try payload.decode(Data.self, forKey: .signature)
      )
      return
    }
    throw DecodingError.dataCorrupted(
      DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown case")
    )
  }

  /// Decodes the application message carried above the opaque transport.
  public static func decoded(_ data: Data) throws -> Self {
    try JSONDecoder().decode(Self.self, from: data)
  }

  /// Encodes the temporary application message above the opaque transport.
  public func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }

  /// Encodes a relay message in the document form that names the
  /// correlation UUID `id`.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CaseKey.self)
    switch self {
    case .failure(let requestID, let reason):
      var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .failure)
      try payload.encode(requestID, forKey: .requestID)
      try payload.encode(reason, forKey: .reason)

    case .identityRequest(let requestID):
      var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .identityRequest)
      try payload.encode(requestID, forKey: .requestID)

    case .identityResponse(let requestID, let certificateDER):
      var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .identityResponse)
      try payload.encode(requestID, forKey: .requestID)
      try payload.encode(certificateDER, forKey: .certificateDER)

    case .signatureRequest(let requestID, let profile, let algorithm, let digest):
      var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .signatureRequest)
      try payload.encode(requestID, forKey: .requestID)
      try payload.encode(profile, forKey: .profile)
      try payload.encode(algorithm, forKey: .algorithm)
      try payload.encode(digest, forKey: .digest)

    case .signatureResponse(let requestID, let signature):
      var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .signatureResponse)
      try payload.encode(requestID, forKey: .requestID)
      try payload.encode(signature, forKey: .signature)
    }
  }
}
