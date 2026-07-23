import CardCore
import Foundation
import Testing

@Suite
internal struct CardOperationsTests {
  @Test
  internal func selectFineidApplicationSucceeds() throws {
    let channel = ScriptedChannel([
      ("00A4040C0CA000000063504B43532D3135", "9000")
    ])
    try CardOperations(channel: channel).selectFineidApplication()
    #expect(channel.isExhausted)
  }

  @Test
  internal func unsupportedCardRejectsTheSelect() {
    let channel = ScriptedChannel([
      ("00A4040C0CA000000063504B43532D3135", "6A82")
    ])
    #expect(throws: CardOperationError.selectRejected(.fileNotFound)) {
      try CardOperations(channel: channel).selectFineidApplication()
    }
  }

  @Test
  internal func readElementaryFileRunsTheFullChain() throws {
    let content = String(repeating: "AB", count: 10)
    let channel = ScriptedChannel([
      ("00A4020C025031", "9000"),
      ("00B0000080", content + "9000"),
    ])
    let read = try CardOperations(channel: channel)
      .readElementaryFile(.objectDirectory, expectedLength: nil)
    #expect(read == WireHex.data(content))
    #expect(channel.isExhausted)
  }

  @Test
  internal func probeReportReadsAllThreeCredentials() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    // PIN1 and PIN2 answer the VERIFY probe; the PUK answers the
    // GET DATA PIN-container query with a DF 21 04 attributes object.
    let channel = ScriptedChannel([
      ("0020001100", "63C5"),
      ("0020008200", "63C5"),
      ("00CB00FF05A00383018300", "DF2104050A0AFF9000"),
    ])
    let report = try CardOperations(channel: channel).probeCredentials()
    #expect(report.pin1 == .remaining(five))
    #expect(report.pin2 == .remaining(five))
    #expect(report.puk == .remaining(five))
    let state = try #require(report.retryState)
    #expect(state.isPristine)
    #expect(channel.isExhausted)
  }

  @Test
  internal func probeClassifiesTerminalStates() throws {
    let channel = ScriptedChannel([
      ("0020001100", "6983"),
      ("0020008200", "9000"),
      ("00CB00FF05A00383018300", "6984"),
    ])
    let operations = CardOperations(channel: channel)
    #expect(try operations.probeRetryCounter(role: .pin1) == .locked)
    #expect(try operations.probeRetryCounter(role: .pin2) == .verified)
    #expect(try operations.probeRetryCounter(role: .puk) == .invalidated)
  }

  @Test
  internal func pukProbeRunsTheGetResponseContinuation() throws {
    // The live-observed T=0 shape: GET DATA answers 61 25 (37 bytes
    // available); GET RESPONSE fetches the attributes object.
    let five = try #require(RetryCount(attemptsRemaining: 5))
    let channel = ScriptedChannel([
      ("00CB00FF05A00383018300", "6125"),
      ("00C0000025", "DF2104050A0AFF9000"),
    ])
    let outcome = try CardOperations(channel: channel)
      .probeRetryCounter(role: .puk)
    #expect(outcome == .remaining(five))
    #expect(channel.isExhausted)
  }

  @Test
  internal func pukAttributesWithoutCounterMeanNoInformation() throws {
    let channel = ScriptedChannel([
      ("00CB00FF05A00383018300", "AABBCCDD9000")
    ])
    let outcome = try CardOperations(channel: channel)
      .probeRetryCounter(role: .puk)
    #expect(outcome == .noInformation)
  }

  @Test
  internal func readTokenSerialParsesTheTokenInfoFile() throws {
    // TokenInfo: SEQUENCE { INTEGER 0, OCTET STRING 6 serial bytes }.
    let tokenInfo = "300B020100040612AB34CD56EF"
    let channel = ScriptedChannel([
      ("00A4020C025032", "9000"),
      ("00B0000080", tokenInfo + "9000"),
    ])
    let serial = try CardOperations(channel: channel).readTokenSerial()
    #expect(serial.value == "12AB34CD56EF")
    #expect(channel.isExhausted)
  }

  @Test
  internal func malformedTokenInfoFailsTyped() {
    let channel = ScriptedChannel([
      ("00A4020C025032", "9000"),
      ("00B0000080", "AABB9000"),
    ])
    #expect(throws: CardOperationError.tokenInfoMalformed) {
      _ = try CardOperations(channel: channel).readTokenSerial()
    }
  }
}
