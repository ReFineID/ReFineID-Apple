import CardCore
import Foundation
import Testing

@Suite
internal struct CertificateReadTests {
  @Test
  internal func authenticationLeafReadsUnderTheApplication() throws {
    // Auth leaf lives under the PKCS#15 application: select app, select
    // EF.4331, read to a short chunk. A tiny synthetic DER stands in.
    let der = String(repeating: "AB", count: 12)
    let channel = ScriptedChannel([
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4020C024331", "9000"),
      ("00B0000080", der + "9000"),
    ])
    let read = try CardOperations(channel: channel)
      .readCertificate(.authentication)
    #expect(read == WireHex.data(der))
    #expect(channel.isExhausted)
  }

  @Test
  internal func issuingCertificateReadsUnderTheMasterFile() throws {
    // Issuer chain lives under MF: select MF, select EF.4336, read.
    let der = String(repeating: "CD", count: 8)
    let channel = ScriptedChannel([
      ("00A4000C023F00", "9000"),
      ("00A4020C024336", "9000"),
      ("00B0000080", der + "9000"),
    ])
    let read = try CardOperations(channel: channel)
      .readCertificate(.issuing)
    #expect(read == WireHex.data(der))
    #expect(channel.isExhausted)
  }

  @Test
  internal func masterFileSelectFallsBackToSelectByName() throws {
    // First MF variant (P1=00) is refused; the by-name variant (P1=04)
    // is tried and succeeds.
    let der = "EEFF"
    let channel = ScriptedChannel([
      ("00A4000C023F00", "6A82"),
      ("00A4040C023F00", "9000"),
      ("00A4020C024334", "9000"),
      ("00B0000080", der + "9000"),
    ])
    let read = try CardOperations(channel: channel)
      .readCertificate(.root)
    #expect(read == WireHex.data(der))
    #expect(channel.isExhausted)
  }

  @Test
  internal func elementaryFileSelectFallsBackToSelectByFileId() throws {
    // Under the app, the EF-under-DF variant (P1=02) is refused; the
    // by-file-id variant (P1=00) succeeds.
    let der = "1234"
    let channel = ScriptedChannel([
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4020C024331", "6A82"),
      ("00A4000C024331", "9000"),
      ("00B0000080", der + "9000"),
    ])
    let read = try CardOperations(channel: channel)
      .readCertificate(.authentication)
    #expect(read == WireHex.data(der))
    #expect(channel.isExhausted)
  }

  @Test
  internal func absentSlotSurfacesAsSelectRejected() {
    let channel = ScriptedChannel([
      ("00A4000C023F00", "9000"),
      ("00A4020C024336", "6A82"),
      ("00A4000C024336", "6A82"),
    ])
    #expect(throws: CardOperationError.selectRejected(.fileNotFound)) {
      _ = try CardOperations(channel: channel).readCertificate(.issuing)
    }
  }

  @Test
  internal func multiChunkCertificateAssemblesInOrder() throws {
    let first = String(repeating: "A1", count: 128)
    let second = String(repeating: "B2", count: 40)
    let channel = ScriptedChannel([
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4020C024331", "9000"),
      ("00B0000080", first + "9000"),
      ("00B0008080", second + "9000"),
    ])
    let read = try CardOperations(channel: channel)
      .readCertificate(.authentication)
    #expect(read == WireHex.data(first + second))
    #expect(channel.isExhausted)
  }
}
