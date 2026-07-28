import CardCore
import Foundation
import Testing

@Suite
internal struct Rsa3072Pkcs1Sha256EncodedMessageTests {
  /// A recognizable but wholly synthetic SHA-256-sized value.
  private static let syntheticDigest = Data((0..<32).map(UInt8.init))

  /// Fixed EMSA-PKCS1-v1_5 SHA-256 DigestInfo prefix.
  private static let digestInfoPrefix: [UInt8] = [
    0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ]

  /// Builds an exact RSA-3072 encoded message without using card data.
  private static func validBlock() -> Data {
    let trailerByteCount = Self.digestInfoPrefix.count + Self.syntheticDigest.count
    let paddingByteCount =
      Rsa3072Pkcs1Sha256EncodedMessage.blockByteCount - trailerByteCount - 3
    var bytes: [UInt8] = [0, 1]
    bytes.append(contentsOf: repeatElement(0xFF, count: paddingByteCount))
    bytes.append(0)
    bytes.append(contentsOf: Self.digestInfoPrefix)
    bytes.append(contentsOf: Self.syntheticDigest)
    return Data(bytes)
  }

  @Test
  internal func acceptsOneExactSyntheticRsa3072Sha256Block() throws {
    let decoded = try #require(
      Rsa3072Pkcs1Sha256EncodedMessage(encoded: Self.validBlock())
    )
    #expect(decoded.digest == Self.syntheticDigest)
  }

  @Test
  internal func refusesWrongWidth() {
    #expect(
      Rsa3072Pkcs1Sha256EncodedMessage(
        encoded: Data(Self.validBlock().dropLast())
      ) == nil
    )
  }

  @Test
  internal func refusesNonFfPadding() {
    var block = Self.validBlock()
    block[2] = 0
    #expect(Rsa3072Pkcs1Sha256EncodedMessage(encoded: block) == nil)
  }

  @Test
  internal func refusesAnotherDigestInfoAlgorithm() {
    var block = Self.validBlock()
    let digestInfoOffset =
      block.count - Self.digestInfoPrefix.count - Self.syntheticDigest.count
    block[digestInfoOffset] ^= 1
    #expect(Rsa3072Pkcs1Sha256EncodedMessage(encoded: block) == nil)
  }
}
