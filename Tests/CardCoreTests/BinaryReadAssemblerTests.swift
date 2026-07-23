import CardCore
import Foundation
import Testing

@Suite
internal struct BinaryReadAssemblerTests {
  @Test
  internal func threeChunkReadMatchesTheOracleScenario() {
    // The reference implementation's continuation test: two full
    // 128-byte chunks, then a short 64-byte chunk ends the read.
    var assembler = BinaryReadAssembler(expectedLength: nil)

    let first = String(repeating: "AA", count: 128)
    let second = String(repeating: "BB", count: 128)
    let third = String(repeating: "CC", count: 64)

    #expect(assembler.nextStep == .transmit(expectedRead("000080")))
    assembler.accept(response(payloadHex: first))

    #expect(assembler.nextStep == .transmit(expectedRead("008080")))
    assembler.accept(response(payloadHex: second))

    #expect(assembler.nextStep == .transmit(expectedRead("010080")))
    assembler.accept(response(payloadHex: third))

    #expect(
      assembler.nextStep
        == .complete(WireHex.data(first + second + third))
    )
  }

  @Test
  internal func expectedLengthTightensTheLastChunk() {
    // A 130-byte expectation: one full chunk, then exactly two bytes.
    var assembler = BinaryReadAssembler(expectedLength: 130)

    let first = String(repeating: "11", count: 128)
    assembler.accept(response(payloadHex: first))
    #expect(assembler.nextStep == .transmit(expectedRead("008002")))

    assembler.accept(response(payloadHex: "2222"))
    #expect(
      assembler.nextStep == .complete(WireHex.data(first + "2222"))
    )
  }

  @Test
  internal func endOfFileStatusEndsTheRead() throws {
    var assembler = BinaryReadAssembler(expectedLength: nil)
    assembler.accept(
      try #require(ResponseApdu(raw: WireHex.data("DEAD6282")))
    )
    #expect(assembler.nextStep == .complete(WireHex.data("DEAD")))
  }

  @Test
  internal func emptyFileFails() throws {
    var assembler = BinaryReadAssembler(expectedLength: nil)
    assembler.accept(try #require(ResponseApdu(raw: WireHex.data("9000"))))
    #expect(assembler.nextStep == .failed(.emptyFile))
  }

  @Test
  internal func unexpectedStatusFails() throws {
    var assembler = BinaryReadAssembler(expectedLength: nil)
    assembler.accept(try #require(ResponseApdu(raw: WireHex.data("6A82"))))
    #expect(assembler.nextStep == .failed(.unexpectedStatus(.fileNotFound)))
  }

  @Test
  internal func oversizedChunkFails() {
    // Expecting at most two bytes; the card returns four.
    var assembler = BinaryReadAssembler(expectedLength: 2)
    assembler.accept(response(payloadHex: "AABBCCDD"))
    #expect(assembler.nextStep == .failed(.oversizedChunk))
  }

  @Test
  internal func responsesAfterTerminalAreIgnored() {
    var assembler = BinaryReadAssembler(expectedLength: 1)
    assembler.accept(response(payloadHex: "AB"))
    let settled = assembler.nextStep
    assembler.accept(response(payloadHex: "FF"))
    #expect(assembler.nextStep == settled)
  }

  @Test
  internal func nonPositiveExpectedLengthMeansNoCap() {
    // A non-positive expected length is treated as "unknown": the read
    // falls back to the aggregate cap rather than failing.
    var assembler = BinaryReadAssembler(expectedLength: 0)
    let full = String(repeating: "11", count: 64)
    assembler.accept(response(payloadHex: full))
    #expect(assembler.nextStep != .failed(.emptyFile))
  }

  @Test
  internal func singleDerObjectReadsExactlyTheDeclaredLength() {
    // The real hardware case: a 1066-byte cert (30 82 04 26 ...) stored
    // in a padded EF. Eight full 128-byte chunks, then the header-
    // derived cap makes the ninth ask for exactly 42 bytes - never the
    // whole-file overrun that returns EOF+0 and truncates.
    var assembler = BinaryReadAssembler(mode: .singleDerObject)
    let header = "308204263082" + String(repeating: "AB", count: 122)
    assembler.accept(response(payloadHex: header))
    for step in 1..<8 {
      #expect(
        assembler.nextStep == .transmit(expectedRead(offset: step * 128, expectedLength: 128)),
        "chunk \(step) should still ask for 128"
      )
      assembler.accept(response(payloadHex: String(repeating: "CD", count: 128)))
    }
    // Read so far: 1024 bytes; declared total 1066 -> final chunk 42.
    #expect(assembler.nextStep == .transmit(expectedRead(offset: 1_024, expectedLength: 42)))
    assembler.accept(response(payloadHex: String(repeating: "EF", count: 42)))
    switch assembler.nextStep {
    case .complete(let content):
      #expect(content.count == 1_066)
    default:
      Issue.record("DER-object read should complete at 1066 bytes")
    }
  }

  @Test
  internal func singleDerObjectTrimsTrailingPadding() {
    // The first chunk already contains the whole short DER object plus
    // padding; the read returns exactly the object.
    var assembler = BinaryReadAssembler(mode: .singleDerObject)
    // SEQUENCE length 4 (30 04 AABBCCDD) then padding to a 16-byte chunk.
    let chunk = "3004AABBCCDD" + String(repeating: "FF", count: 10)
    assembler.accept(response(payloadHex: chunk))
    #expect(assembler.nextStep == .complete(WireHex.data("3004AABBCCDD")))
  }

  private func response(payloadHex: String) -> ResponseApdu {
    guard let response = ResponseApdu(raw: WireHex.data(payloadHex + "9000")) else {
      preconditionFailure("invalid response vector")
    }
    return response
  }

  private func expectedRead(offset: Int, expectedLength: Int) -> CommandApdu {
    guard
      let readOffset = ReadOffset(value: UInt16(offset)),
      let length = ExpectedResponseLength(count: expectedLength)
    else {
      preconditionFailure("invalid expected-read vector")
    }
    return CommandApdu.readBinary(offset: readOffset, expectedLength: length)
  }

  private func expectedRead(_ offsetAndLengthHex: String) -> CommandApdu {
    let raw = WireHex.data("00B0" + offsetAndLengthHex)
    let bytes = Array(raw)
    guard
      let offset = ReadOffset(
        value: UInt16(bytes[2]) << 8 | UInt16(bytes[3])
      ),
      let length = ExpectedResponseLength(
        count: bytes[4] == 0 ? ExpectedResponseLength.maximum : Int(bytes[4])
      )
    else {
      preconditionFailure("invalid expected-read vector")
    }
    return CommandApdu.readBinary(offset: offset, expectedLength: length)
  }
}
