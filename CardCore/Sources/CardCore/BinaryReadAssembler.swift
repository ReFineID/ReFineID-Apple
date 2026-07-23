import Foundation

/// A pure state machine that reads the currently selected EF in bounded
/// chunks, mirroring the reference implementation's loop.
///
/// Two modes. `.toEndOfFile` reads until a short chunk, an empty chunk,
/// an end-of-file status, or the aggregate cap. `.singleDerObject` reads
/// exactly the one DER object at the file's start: once the object's
/// header is in hand its declared length becomes the cap, so the final
/// chunk asks for exactly the remaining bytes. That matters because the
/// card refuses a READ BINARY whose length overruns the file - it
/// returns end-of-file with zero bytes rather than a partial - so a
/// certificate (whose DER is shorter than the padded EF) must be read to
/// its exact size or it comes back truncated.
///
/// The assembler performs no I/O. `nextStep` says what to do; every
/// `transmit` response is fed back through `accept(_:)`. This keeps the
/// continuation logic fully testable without a card and lets the
/// transport stay a thin, dumb layer.
public struct BinaryReadAssembler: Equatable, Sendable {
  /// How the read decides it is complete.
  public enum Mode: Equatable, Sendable {
    /// Read to a short/empty chunk, end-of-file, or the aggregate cap.
    case toEndOfFile

    /// Read exactly the single DER object at offset zero.
    case singleDerObject
  }

  /// Chunk size per READ BINARY, the FINEID published guideline value.
  public static let chunkLength: Int = 128

  /// Aggregate cap: no supported file is larger than 16 KiB; a read
  /// that would exceed this fails rather than trusting the card.
  public static let maximumTotalLength: Int = 16_384

  private let mode: Mode
  private var collected: Data
  private var offset: Int
  private var cap: Int
  private var terminal: BinaryReadStep?

  /// The next thing to do: transmit, or a terminal completion/failure.
  public var nextStep: BinaryReadStep {
    if let terminal {
      return terminal
    }
    let want = min(cap - offset, Self.chunkLength)
    guard
      let readOffset = ReadOffset(value: UInt16(offset)),
      let expected = ExpectedResponseLength(count: want)
    else {
      preconditionFailure("assembler invariant: offset within bounds")
    }
    return .transmit(
      .readBinary(offset: readOffset, expectedLength: expected)
    )
  }

  /// Starts a read.
  ///
  /// `.toEndOfFile` with an expected length tightens the cap to it (pass
  /// nil to read up to the aggregate cap). `.singleDerObject` derives
  /// the cap from the object header as it arrives.
  public init(mode: Mode = .toEndOfFile, expectedLength: Int? = nil) {
    if let expectedLength, expectedLength >= 1 {
      self.cap = min(expectedLength, Self.maximumTotalLength)
    } else {
      self.cap = Self.maximumTotalLength
    }
    self.mode = mode
    self.collected = Data()
    self.offset = 0
  }

  /// Feeds the response to the outstanding `transmit` step.
  ///
  /// Responses arriving after a terminal step are ignored.
  public mutating func accept(_ response: ResponseApdu) {
    guard terminal == nil else { return }
    let endOfFile = response.statusWord == .endOfFile
    guard response.statusWord == .success || endOfFile else {
      terminal = .failed(.unexpectedStatus(response.statusWord))
      return
    }
    let want = min(cap - offset, Self.chunkLength)
    guard response.payload.count <= want else {
      terminal = .failed(.oversizedChunk)
      return
    }
    collected.append(response.payload)
    offset += response.payload.count
    tightenCapForDerObject()

    if mode == .singleDerObject, offset >= cap {
      terminal = .complete(collected.prefix(cap))
      return
    }
    let shortChunk = response.payload.count < want
    if response.payload.isEmpty || shortChunk || endOfFile || offset >= cap {
      terminal = collected.isEmpty ? .failed(.emptyFile) : .complete(collected)
    }
  }

  /// In DER mode, once the object header has arrived, sets the cap to
  /// the object's declared total so the final chunk is sized exactly.
  private mutating func tightenCapForDerObject() {
    guard mode == .singleDerObject, cap == Self.maximumTotalLength else {
      return
    }
    if let total = DerObjectLength.total(of: collected), total >= 1 {
      cap = min(total, Self.maximumTotalLength)
    }
  }
}
