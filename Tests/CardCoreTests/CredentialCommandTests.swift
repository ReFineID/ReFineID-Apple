import CardCore
import Foundation
import Testing

/// Wire vectors and answer classification for the credential commands.
///
/// Vectors follow FINEID S1 v4.2 §3.5 and are cross-checked against the
/// Rust reference implementation.
@Suite
internal struct CredentialCommandTests {
  @Test
  internal func verifyPin2MatchesTheWireVector() {
    // 00 20 00 82 0C, then "123456" right-padded with zero bytes to
    // twelve (S1 v4.2 §3.5.2).
    guard let pin = Pin2(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.verifyPin2(
      pin.consumeForSingleTransmission()
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data("002000820C313233343536000000000000")
    )
  }

  @Test
  internal func changePin1MatchesTheWireVector() {
    // 00 24 00 11 18, then the current and the new PIN each padded to
    // twelve (S1 v4.2 §3.5.3).
    guard
      let current = Pin1(digits: "1234"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.changePin1(
      current: current.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission()
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "0024001118313233340000000000000000343332310000000000000000")
    )
  }

  @Test
  internal func changePin2MatchesTheWireVector() {
    // The PIN2 form differs from `changePin1` only in the reference
    // byte (S1 v4.2 §3.5.3).
    guard
      let current = Pin2(digits: "123456"),
      let new = Pin2(digits: "654321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.changePin2(
      current: current.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission()
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "0024008218313233343536000000000000363534333231000000000000")
    )
  }

  @Test
  internal func unblockPin1MatchesTheWireVector() {
    // 00 2C 00 11 18, then the PUK and the new PIN each padded to
    // twelve (S1 v4.2 §3.5.4).
    guard
      let puk = Puk(digits: "12345678"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    let command = CredentialBearingCommand.unblockPin1(
      puk: puk.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission()
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "002C001118313233343536373800000000343332310000000000000000")
    )
  }

  @Test
  internal func unblockPin1PadsASevenDigitPukToTwelve() {
    // A seven-digit activation PUK pads to the same stored length as
    // everything else (S1 v4.2 §3.5.4).
    guard
      let puk = Puk(digits: "4907123"),
      let new = Pin1(digits: "4907")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    let command = CredentialBearingCommand.unblockPin1(
      puk: puk.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission()
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "002C001118343930373132330000000000343930370000000000000000")
    )
  }

  @Test
  internal func unblockPin2MatchesTheWireVector() {
    // The PIN2 form differs from `unblockPin1` only in the target
    // reference byte (S1 v4.2 §3.5.4).
    guard
      let puk = Puk(digits: "12345678"),
      let new = Pin2(digits: "654321")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    let command = CredentialBearingCommand.unblockPin2(
      puk: puk.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission()
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "002C008218313233343536373800000000363534333231000000000000")
    )
  }
}
