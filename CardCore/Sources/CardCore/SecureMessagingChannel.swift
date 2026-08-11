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

/// A `CardChannel` decorator that carries every APDU inside the ISO 7816-4
/// secure-messaging envelope PACE established.
///
/// This decorator is constructed ONLY on the contactless branch. PACE is the
/// contactless door and these keys are what it yields; the contact path
/// transmits plain APDUs on the bare transport and never sees this type. No
/// layer above can tell the two apart, because the decorator hands back
/// UNWRAPPED INNER bytes -- the plaintext body followed by the status word
/// that travelled in DO'99' -- so `CardOperations`, `BinaryReadAssembler`
/// and everything above them are unchanged by the transport choice.
///
/// A command is protected as DO'87' (the ISO 7816-4 padded plaintext under
/// AES-256-CBC, with the send-sequence counter encrypted under Kenc as the
/// IV), DO'97' (the enclosed command's Le) and DO'8E' (the leading eight
/// bytes of an AES-CMAC over the padded concatenation of the counter, the
/// padded header, DO'87' and DO'97'). The class byte gets the
/// secure-messaging bits before the header is MACed, which is what binds
/// the header to the cryptogram.
///
/// The channel owns the send-sequence counter and pre-increments it in BOTH
/// directions, so a command uses counter `n` and its response `n + 1`, in
/// lockstep with the card.
///
/// Provenance: lifted from the ReFineID iOS browser donor
/// `Sources/ReFineIDBrowserKit/Card/SecureMessaging.swift` and the
/// `SecureCardSession` transmit of
/// `Sources/ReFineIDBrowserKit/Card/CardSession.swift`.
public final class SecureMessagingChannel: CardChannel {
  /// Why a protected exchange was refused.
  public enum Failure: Error, Equatable {
    /// The response's DO'8E' did not match the checksum computed over the
    /// received data objects. The channel is no longer trustworthy.
    case macMismatch

    /// The command handed in was not a short-form APDU this layer can
    /// take apart.
    case malformedCommand

    /// The response carried a secure-messaging body that was not the
    /// expected data objects.
    case malformedResponse

    /// The protected body would not fit a short-form command.
    case oversizedCommand
  }

  /// The pieces of a plain command that secure messaging protects
  /// separately: the header (already carrying the secure-messaging class
  /// bits, because the MAC covers it in that form), the data field, and Le.
  private struct PlainCommandParts {
    /// The four header bytes, class byte already marked.
    let header: Data

    /// The command data field, empty when the command carries none.
    let data: Data

    /// The enclosed command's Le, nil when it expects no response data.
    let expectedLength: UInt8?
  }

  /// The secure-messaging data objects of a response.
  private struct ResponseObjects {
    /// DO'87', the padding indicator followed by the cryptogram; nil when
    /// the response carried no data.
    let cryptogram: Data?

    /// DO'99', the two status bytes of the enclosed plain response.
    let status: Data

    /// DO'8E', the truncated checksum.
    let mac: Data
  }

  /// The four header bytes of any APDU.
  private static let headerLength: Int = 4

  /// The largest body a short-form command APDU can carry.
  private static let maximumBodyLength: Int = 255

  /// Chunked reads over this channel ask for the secure-messaged chunk,
  /// never the plain one.
  ///
  /// Everything above this decorator is unchanged by the transport
  /// choice except for this one number, and it cannot be left out: a
  /// chunk whose DO'87' cryptogram, DO'99' and DO'8E' overran one
  /// short-form response would come back short on every read, and a read
  /// to end of file would take the first short chunk for the end of the
  /// file and return a truncated certificate with no error at all.
  public var readChunkLength: ReadChunkLength {
    .secureMessaged
  }

  /// The transport underneath, which sees only protected APDUs.
  private let plainChannel: any CardChannel

  /// Kenc, the encryption key.
  private let encryptionKey: Data

  /// Kmac, the authentication key.
  private let macKey: Data

  /// The send-sequence counter, pre-incremented in both directions.
  private var sendSequenceCounter: Data

  /// Wraps `channel` in the session `sessionKeys` describes.
  ///
  /// Constructed only on the contactless branch, immediately after a
  /// successful PACE run and before any other command is sent: the counter
  /// starts at zero and the card's does too, so nothing may pass through
  /// the plain channel once this exists.
  public init(wrapping channel: any CardChannel, sessionKeys: PaceSessionKeys) {
    self.plainChannel = channel
    self.encryptionKey = sessionKeys.encryptionKey
    self.macKey = sessionKeys.macKey
    self.sendSequenceCounter = sessionKeys.initialSendSequenceCounter
  }

  /// Splits a plain short-form command and marks its class byte.
  ///
  /// Extended-length APDUs are refused rather than mis-parsed; nothing in
  /// this driver builds one.
  private static func commandParts(of plain: Data) throws -> PlainCommandParts {
    let bytes = Array(plain)
    guard bytes.count >= Self.headerLength else { throw Failure.malformedCommand }
    var header = Data(bytes.prefix(Self.headerLength))
    header[header.startIndex] |= PaceValues.classSecureMessagingBit
    if bytes.count == Self.headerLength {
      return PlainCommandParts(header: header, data: Data(), expectedLength: nil)
    }
    if bytes.count == Self.headerLength + 1 {
      return PlainCommandParts(
        header: header,
        data: Data(),
        expectedLength: bytes[Self.headerLength]
      )
    }
    let dataStart = Self.headerLength + 1
    let dataLength = Int(bytes[Self.headerLength])
    guard dataLength > 0, bytes.count >= dataStart + dataLength else {
      throw Failure.malformedCommand
    }
    let data = Data(bytes[dataStart..<dataStart + dataLength])
    if bytes.count == dataStart + dataLength {
      return PlainCommandParts(header: header, data: data, expectedLength: nil)
    }
    guard bytes.count == dataStart + dataLength + 1 else {
      throw Failure.malformedCommand
    }
    return PlainCommandParts(
      header: header,
      data: data,
      expectedLength: bytes[dataStart + dataLength]
    )
  }

  /// The secure-messaging data objects carried by a response body.
  ///
  /// DO'99' and DO'8E' are both mandatory: the real status word never
  /// travels in the clear, so a response without a verified DO'99' has no
  /// status at all.
  private static func responseObjects(in body: Data) throws -> ResponseObjects {
    guard let records = try? DerTlvRecord.sequence(in: body) else {
      throw Failure.malformedResponse
    }
    var cryptogram: Data?
    var status: Data?
    var mac: Data?
    for record in records {
      switch record.tag {
      case PaceValues.cryptogramTag:
        cryptogram = record.value
      case PaceValues.statusTag:
        status = record.value
      case PaceValues.macTag:
        mac = record.value
      default:
        continue
      }
    }
    guard
      let status, status.count == ResponseApdu.statusWordLength,
      let mac, mac.count == PaceValues.macLength
    else {
      throw Failure.malformedResponse
    }
    return ResponseObjects(cryptogram: cryptogram, status: status, mac: mac)
  }

  /// ISO 7816-4 padding method 2: append `80`, then `00` to the block
  /// boundary.
  ///
  /// Padding is unconditional, so an already-aligned buffer gains a whole
  /// extra block. That is what makes stripping it unambiguous.
  private static func padded(_ data: Data) -> Data {
    var buffer = data
    buffer.append(PaceValues.paddingMarkerByte)
    let remainder = buffer.count % AesCbc.blockSize
    if remainder != 0 {
      buffer.append(
        contentsOf: repeatElement(0, count: AesCbc.blockSize - remainder)
      )
    }
    return buffer
  }

  /// Strips ISO 7816-4 padding method 2, returning the input unchanged
  /// when it carries no marker.
  private static func unpadded(_ data: Data) -> Data {
    let bytes = Array(data)
    var end = bytes.count
    while end > 0, bytes[end - 1] == 0 {
      end -= 1
    }
    guard end > 0, bytes[end - 1] == PaceValues.paddingMarkerByte else {
      return data
    }
    return Data(bytes[0..<(end - 1)])
  }

  /// Protects one plain command, transmits it, and returns the unwrapped
  /// inner response as `payload || SW1 SW2`.
  ///
  /// The outer response is assembled across `61xx` continuations first,
  /// because the envelope's overhead pushes it past what a single
  /// short-form response can carry.
  ///
  /// Then the critical rule, carried from the donor: unwrap whenever there
  /// is a secure-messaging body, EVEN IF the outer status word is an error.
  /// A card answering READ BINARY at end of file returns `6282` at the
  /// outer level while still protecting the response, DO'8E' included --
  /// and it has already incremented its own send-sequence counter to
  /// produce that checksum. Returning early on the outer error would leave
  /// this side one behind forever, and every later APDU would fail its MAC
  /// for no visible reason. Only a response with no body at all -- a bare
  /// transport-level failure the card never protected -- is passed through
  /// untouched.
  public func transmit(_ payload: Data) throws -> Data {
    let outer = try ContinuedResponse.transmitting(
      try wrap(payload),
      over: plainChannel
    )
    guard !outer.payload.isEmpty else { return outer.encoded }
    let unwrapped = try unwrap(outer.payload)
    var response = unwrapped.payload
    response.append(unwrapped.status)
    return response
  }

  /// DO'87' for a command data field: the padding indicator followed by
  /// the padded plaintext under AES-256-CBC, or empty when the command
  /// carries no data.
  private func cryptogramObject(for data: Data) throws -> Data {
    guard !data.isEmpty else { return Data() }
    var value = Data([PaceValues.paddingContentIndicator])
    value.append(
      try AesCbc.encrypt(
        key: encryptionKey,
        initializationVector: try currentInitializationVector(),
        plaintext: Self.padded(data)
      )
    )
    guard let object = DerTlvRecord.encoded(tag: PaceValues.cryptogramTag, value: value)
    else {
      throw Failure.oversizedCommand
    }
    return object
  }

  /// DO'97' for the enclosed command's Le, or empty when it has none.
  private func expectedLengthObject(for expectedLength: UInt8?) throws -> Data {
    guard let expectedLength else { return Data() }
    guard
      let object = DerTlvRecord.encoded(
        tag: PaceValues.expectedLengthTag,
        value: Data([expectedLength])
      )
    else {
      throw Failure.oversizedCommand
    }
    return object
  }

  /// Builds the protected form of a plain command.
  private func wrap(_ plain: Data) throws -> Data {
    let parts = try Self.commandParts(of: plain)
    incrementSendSequenceCounter()
    let cryptogramObject = try cryptogramObject(for: parts.data)
    let expectedLengthObject = try expectedLengthObject(for: parts.expectedLength)

    var macInput = sendSequenceCounter
    macInput.append(Self.padded(parts.header))
    macInput.append(cryptogramObject)
    macInput.append(expectedLengthObject)
    guard
      let macObject = DerTlvRecord.encoded(
        tag: PaceValues.macTag,
        value: try AesCmac.secureMessagingTag(
          key: macKey,
          message: Self.padded(macInput)
        )
      )
    else {
      throw Failure.oversizedCommand
    }

    let body = cryptogramObject + expectedLengthObject + macObject
    guard body.count <= Self.maximumBodyLength else {
      throw Failure.oversizedCommand
    }
    var wrapped = parts.header
    wrapped.append(UInt8(body.count))
    wrapped.append(body)
    wrapped.append(Iso7816Values.expectedLengthMaximumEncoding)
    return wrapped
  }

  /// Verifies and decrypts a protected response body.
  ///
  /// The checksum is recomputed over the counter and the data objects
  /// RE-ENCODED from their parsed values, never over a slice of the
  /// received bytes: verifying what was parsed is what makes the check
  /// meaningful.
  private func unwrap(_ body: Data) throws -> (payload: Data, status: Data) {
    incrementSendSequenceCounter()
    let objects = try Self.responseObjects(in: body)

    var macInput = sendSequenceCounter
    if let cryptogram = objects.cryptogram {
      guard
        let object = DerTlvRecord.encoded(
          tag: PaceValues.cryptogramTag,
          value: cryptogram
        )
      else {
        throw Failure.malformedResponse
      }
      macInput.append(object)
    }
    guard
      let statusObject = DerTlvRecord.encoded(
        tag: PaceValues.statusTag,
        value: objects.status
      )
    else {
      throw Failure.malformedResponse
    }
    macInput.append(statusObject)
    let computed = try AesCmac.secureMessagingTag(
      key: macKey,
      message: Self.padded(macInput)
    )
    guard ConstantTimeComparison.equal(computed, objects.mac) else {
      throw Failure.macMismatch
    }

    guard let cryptogram = objects.cryptogram else {
      return (Data(), objects.status)
    }
    guard cryptogram.first == PaceValues.paddingContentIndicator else {
      throw Failure.malformedResponse
    }
    let ciphertext = Data(cryptogram.dropFirst())
    guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: AesCbc.blockSize) else {
      throw Failure.malformedResponse
    }
    let plaintext = try AesCbc.decrypt(
      key: encryptionKey,
      initializationVector: try currentInitializationVector(),
      ciphertext: ciphertext
    )
    return (Self.unpadded(plaintext), objects.status)
  }

  /// The CBC initialization vector for the current counter value: the
  /// counter encrypted under Kenc with the raw block cipher
  /// (ICAO 9303-11 section 9.8.7).
  private func currentInitializationVector() throws -> Data {
    try AesCbc.encryptBlock(key: encryptionKey, block: sendSequenceCounter)
  }

  /// Adds one to the counter, big-endian, wrapping from the last byte.
  private func incrementSendSequenceCounter() {
    var index = sendSequenceCounter.count - 1
    while index >= 0, sendSequenceCounter[index] == UInt8.max {
      sendSequenceCounter[index] = 0
      index -= 1
    }
    guard index >= 0 else { return }
    sendSequenceCounter[index] += 1
  }
}
