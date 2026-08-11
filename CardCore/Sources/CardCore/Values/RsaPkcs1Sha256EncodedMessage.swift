//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
import Foundation

/// A validated RSA EMSA-PKCS1-v1_5 SHA-256 encoded message.
///
/// CryptoTokenKit can expose a smart-card RSA request as the raw private
/// key primitive after Security.framework has already built this block.
/// The FINEID card accepts the original digest, so this type performs the
/// strict inverse: exact profile-selected modulus width, complete padding
/// grammar, exact SHA-256 DigestInfo prefix, then the final 32-byte digest.
public struct RsaPkcs1Sha256EncodedMessage: Equatable, Sendable {
  /// SHA-256 digest width in bytes.
  private static let digestByteCount = 32

  /// PKCS#1 requires at least eight FF padding bytes.
  private static let minimumPaddingByteCount = 8

  // Fixed PKCS#1 and SHA-256 DigestInfo wire values.
  // swiftlint:disable no_magic_numbers
  private static let blockPrefix: [UInt8] = [0x00, 0x01]
  private static let paddingByte: UInt8 = 0xFF
  private static let separatorByte: UInt8 = 0x00
  private static let sha256DigestInfoPrefix: [UInt8] = [
    0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ]
  // swiftlint:enable no_magic_numbers

  /// The SHA-256 digest recovered from the validated block.
  public let digest: Data

  /// Validates one complete block against the selected RSA profile.
  public init?(encoded: Data, profile: CardKeyProfile) {
    let blockByteCount: Int
    switch profile {
    case .ecdsaP256, .ecdsaP384:
      return nil
    case .rsa2048, .rsa3072:
      blockByteCount = profile.rawSignatureLength
    }
    let bytes = Array(encoded)
    let digestInfoByteCount = Self.sha256DigestInfoPrefix.count + Self.digestByteCount
    let digestInfoOffset = blockByteCount - digestInfoByteCount
    let separatorOffset = digestInfoOffset - 1
    guard
      bytes.count == blockByteCount,
      bytes.starts(with: Self.blockPrefix),
      separatorOffset - Self.blockPrefix.count >= Self.minimumPaddingByteCount,
      bytes[Self.blockPrefix.count..<separatorOffset]
        .allSatisfy({ $0 == Self.paddingByte }),
      bytes[separatorOffset] == Self.separatorByte,
      Array(
        bytes[
          digestInfoOffset..<(digestInfoOffset + Self.sha256DigestInfoPrefix.count)
        ]) == Self.sha256DigestInfoPrefix
    else {
      return nil
    }
    let digestOffset = digestInfoOffset + Self.sha256DigestInfoPrefix.count
    self.digest = Data(bytes[digestOffset...])
  }
}
