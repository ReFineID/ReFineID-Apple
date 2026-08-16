// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(ReFineIDRapp)
  import Foundation
  import ReFineIDRapp
  import Security

  public enum RappPlatformPrimitiveError: Error, Sendable {
    case entropyUnavailable
    case invalidByteCount
  }

  public struct RappPlatformEntropy: Sendable {
    public init() {}

    public func offerID() throws -> Data {
      try bytes(count: rappRandomByteCounts().offerId)
    }

    public func pairingSecret() throws -> Data {
      try bytes(count: rappRandomByteCounts().pairingSecret)
    }

    public func sessionReadyNonce() throws -> Data {
      try bytes(count: rappRandomByteCounts().sessionReadyNonce)
    }

    public func operationID() throws -> Data {
      try bytes(count: rappRandomByteCounts().operationId)
    }

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

  public struct RappPlatformClock: Sendable {
    private static let nanosecondsPerMillisecond: UInt64 = 1_000_000
    private static let secondsPerMillisecond = 1_000.0

    public init() {}

    public func wallMilliseconds() -> UInt64 {
      UInt64(Date().timeIntervalSince1970 * Self.secondsPerMillisecond)
    }

    public func monotonicMilliseconds() -> UInt64 {
      DispatchTime.now().uptimeNanoseconds / Self.nanosecondsPerMillisecond
    }
  }
#endif
