// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One stream preamble and how it is judged.
internal struct StreamRendezvousVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case accepted
    case encodedHex = "encoded_hex"
    case error
    case name
    case purpose
    case rendezvousTokenHex = "rendezvous_token_hex"
  }

  internal let name: String
  internal let accepted: Bool
  internal let purpose: String
  internal let encodedHex: String
  internal let rendezvousTokenHex: String?
  internal let error: String?
}
