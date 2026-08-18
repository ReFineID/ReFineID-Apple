// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One correlated request or response on the encrypted local relay.
public enum PersistentRelayMessage: Codable, Equatable, Sendable {
  case failure(id: UUID, reason: PersistentRelayFailure)
  case identityRequest(id: UUID)
  case identityResponse(id: UUID, certificateDER: Data)
  case signatureRequest(
    id: UUID,
    profile: PersistentRelayCardProfile,
    algorithm: PersistentRelaySigningAlgorithm,
    digest: Data
  )
  case signatureResponse(id: UUID, signature: Data)

  /// The correlation ID shared by a request and its answer.
  public var requestID: UUID {
    switch self {
    case .identityRequest(let id), .identityResponse(let id, _),
      .signatureRequest(let id, _, _, _), .signatureResponse(let id, _),
      .failure(let id, _):
      id
    }
  }

  /// Decodes the application message carried above the opaque transport.
  public static func decoded(_ data: Data) throws -> Self {
    try JSONDecoder().decode(Self.self, from: data)
  }

  /// Encodes the temporary application message above the opaque transport.
  public func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }
}
