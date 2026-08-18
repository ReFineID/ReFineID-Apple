// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  import Security

  /// Failures raised while producing platform entropy.
  public enum RappPlatformPrimitiveError: Error, Sendable {
    case entropyUnavailable
    case invalidByteCount
  }

  /// System randomness at the byte counts the Rust core publishes.
  public struct RappPlatformEntropy: Sendable {
    /// Creates a stateless entropy source.
    public init() {}

    /// Returns a fresh pairing offer identifier.
    public func offerID() throws -> Data {
      try bytes(count: rappRandomByteCounts().offerId)
    }

    /// Returns a fresh pairing secret.
    public func pairingSecret() throws -> Data {
      try bytes(count: rappRandomByteCounts().pairingSecret)
    }

    /// Returns a fresh session-ready nonce.
    public func sessionReadyNonce() throws -> Data {
      try bytes(count: rappRandomByteCounts().sessionReadyNonce)
    }

    /// Returns a fresh operation identifier.
    public func operationID() throws -> Data {
      try bytes(count: rappRandomByteCounts().operationId)
    }

    /// Returns a fresh liveness challenge.
    public func livenessChallenge() throws -> Data {
      try bytes(count: rappRandomByteCounts().livenessChallenge)
    }

    private func bytes(count: UInt64) throws -> Data {
      guard count > 0, count <= UInt64(Int.max) else {
        throw RappPlatformPrimitiveError.invalidByteCount
      }
      var value = Data(count: Int(count))
      let status = value.withUnsafeMutableBytes { buffer in
        guard let address = buffer.baseAddress else { return errSecParam }
        return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
      }
      guard status == errSecSuccess else {
        value.resetBytes(in: value.startIndex..<value.endIndex)
        throw RappPlatformPrimitiveError.entropyUnavailable
      }
      return value
    }
  }

  /// Wall and monotonic clocks in the millisecond units RAPP uses.
  public struct RappPlatformClock: Sendable {
    private static let nanosecondsPerMillisecond: UInt64 = 1_000_000
    private static let secondsPerMillisecond = 1_000.0

    /// Creates a system-backed clock.
    public init() {}

    /// Milliseconds since the Unix epoch; moves with wall-clock changes.
    public func wallMilliseconds() -> UInt64 {
      UInt64(Date().timeIntervalSince1970 * Self.secondsPerMillisecond)
    }

    /// Milliseconds of monotonic uptime; never moves backwards.
    public func monotonicMilliseconds() -> UInt64 {
      DispatchTime.now().uptimeNanoseconds / Self.nanosecondsPerMillisecond
    }
  }
#endif
