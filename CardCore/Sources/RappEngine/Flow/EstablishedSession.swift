// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// A healthy session that carries operations.
internal struct EstablishedSession {
  internal let role: EndpointRole

  internal let pairIdentifier: Data

  internal let sessionIdentifier: Data

  private var channel: RappMessageChannel?

  internal var isOpen: Bool { channel != nil }

  /// The highest peer sequence accepted, for close and liveness bodies.
  internal var lastReceivedSequence: UInt64 { channel?.lastReceivedSequence ?? 0 }

  internal init(
    role: EndpointRole,
    pairIdentifier: Data,
    sessionIdentifier: Data,
    channel: RappMessageChannel
  ) {
    self.role = role
    self.pairIdentifier = pairIdentifier
    self.sessionIdentifier = sessionIdentifier
    self.channel = channel
  }

  internal mutating func seal(
    _ messageType: MessageType, body: [String: WireValue]
  ) throws -> Data {
    guard var working = channel else { throw SessionError.closed }
    let frame: Data
    do {
      frame = try working.seal(messageType, body: body)
    } catch {
      throw SessionError.noise
    }
    channel = working
    return frame
  }

  internal mutating func open(_ frame: Data) throws -> Envelope {
    guard var working = channel else { throw SessionError.closed }
    let envelope: Envelope
    do {
      envelope = try working.open(frame)
    } catch RappOpenFailure.sessionIntegrityFailure {
      channel = nil
      throw SessionError.integrityFailure
    } catch {
      // The frame decrypted, so it came from the paired peer holding the
      // right key; only its contents were unreadable. That ends this
      // session and nothing more. Ending the pairing would answer a
      // message this side could not parse by making the holder scan a new
      // code -- and a peer that can still decrypt is not the threat that
      // revocation exists for.
      channel = nil
      throw SessionError.unexpectedMessage
    }
    channel = working
    return envelope
  }

  /// Close this session locally.
  ///
  /// The pairing itself is untouched.
  internal mutating func close() {
    channel = nil
  }
}
