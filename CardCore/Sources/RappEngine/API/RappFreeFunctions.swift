// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How many random bytes each generated value needs.
///
/// The engine states the sizes; the caller owns the random source.
public func rappRandomByteCounts() -> RappRandomByteCounts {
  RappRandomByteCounts(
    offerId: UInt64(OfferLimit.offerIdentifierSize),
    pairingSecret: UInt64(OfferLimit.pairingSecretSize),
    sessionReadyNonce: UInt64(FlowLimit.readyNonce),
    operationId: UInt64(OperationSize.operationIdentifier),
    livenessChallenge: UInt64(PingChallenge.byteCount))
}

/// The preamble a dialing proxy sends to open a pairing ceremony.
public func rappStreamPairingPreamble() -> Data {
  // The pairing preamble carries no token, so its encoding cannot fail.
  (try? StreamRendezvous.pairing.encoded()) ?? Data()
}

/// The name of the stream transport profile.
public func rappStreamProfileName() -> String {
  StreamProfile.name
}

/// The preamble a dialing proxy sends to reach a stored pairing.
///
/// - Throws: ``RappBindingError/InvalidInput`` when the token is
///   not the size the specification fixes.
public func rappStreamSessionPreamble(rendezvousToken: Data) throws -> Data {
  guard rendezvousToken.count == StreamRendezvous.tokenSize else {
    throw RappBindingError.InvalidInput
  }
  do {
    return try StreamRendezvous.session(token: rendezvousToken).encoded()
  } catch {
    throw RappBindingError.InvalidInput
  }
}
