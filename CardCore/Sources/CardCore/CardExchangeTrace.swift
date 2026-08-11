// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import Foundation

/// One card exchange, as the single line a trace records it on.
///
/// The line is the smallest thing that still answers the question a
/// failed login asks: which instruction was sent, how much went each way,
/// what the card answered, and how long the card took. Everything else
/// about an APDU -- the data field above all -- is left out, because a
/// trace that carried payloads would eventually carry a certificate, a
/// serial, or a PIN block.
///
/// VERIFY is redacted wholesale. Its data field is the padded PIN block,
/// and its length is the one thing about that block worth guessing at, so
/// neither is written: the instruction, the status word (which carries
/// the retry counter, and is exactly what a failed login needs) and the
/// elapsed time, and nothing else.
public enum CardExchangeTrace {
  /// Position of the instruction byte in a command APDU: CLA INS P1 P2.
  private static let instructionIndex: Int = 1

  /// One byte as two uppercase hex digits.
  private static let byteFormat: String = "%02X"

  /// One status word as four uppercase hex digits.
  private static let wordFormat: String = "%04X"

  /// What is printed where a value could not be read.
  private static let unknown: String = "?"

  /// What is printed in place of a redacted value.
  private static let redacted: String = "redacted"

  /// How many leading command bytes a debug trace shows.
  ///
  /// Enough for the header, length and the first of the data field, which
  /// is what distinguishes one PACE step from another.
  private static let tracedHeadLength: Int = 12

  /// One exchange as a trace line.
  ///
  /// `response` is the raw transport answer including its status word, or
  /// nil when the transport produced none at all -- a distinction worth
  /// keeping, because "the card said nothing" and "the card refused" are
  /// different faults with the same visible symptom.
  public static func line(request: Data, response: Data?, elapsed: Duration) -> String {
    let answer = response.flatMap(ResponseApdu.init(raw:))
    let status = answer.map { String(format: Self.wordFormat, $0.statusWord.encoded) }
    let received = answer.map { String($0.payload.count) }
    let tail =
      " rx=" + (received ?? Self.unknown)
      + " sw=" + (status ?? Self.unknown)
      + " ms=" + TraceTiming.milliseconds(elapsed)
    guard let instruction = Self.instruction(of: request) else {
      return "apdu ins=" + Self.unknown + " tx=\(request.count)" + tail
    }
    let named = "apdu ins=" + String(format: Self.byteFormat, instruction)
    guard instruction != Iso7816Values.insVerify else {
      return named + " verify tx=" + Self.redacted + tail
    }
    #if DEBUG
      // The header and a little of the body, while the contactless path
      // is still being brought up: an instruction byte alone cannot show
      // that two implementations send the same command, and that
      // comparison is the whole of the current work. SELECT, MSE and
      // GENERAL AUTHENTICATE carry no secret -- VERIFY returned above,
      // before reaching this line, and is the only command that does.
      let head = request.prefix(Self.tracedHeadLength)
        .map { String(format: Self.byteFormat, $0) }
        .joined()
      return named + " tx=\(request.count) head=" + head + tail
    #else
      return named + " tx=\(request.count)" + tail
    #endif
  }

  /// The instruction byte, or nil when the payload is too short to have
  /// one.
  private static func instruction(of request: Data) -> UInt8? {
    let header = Array(request.prefix(Self.instructionIndex + 1))
    guard header.count > Self.instructionIndex else { return nil }
    return header[Self.instructionIndex]
  }
}
