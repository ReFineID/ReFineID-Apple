import CardCore
import CryptoTokenKit
import Foundation

/// Adapts a `TKSmartCard` to CardCore's synchronous `CardChannel` for the
/// app's status and diagnostic reads, and opens the exclusive session.
///
/// Same shape as the extension's adapter: each APDU is driven with a
/// completion handler plus a `DispatchSemaphore` (the reply fires on
/// `TKSmartCard`'s own queue), never Swift concurrency. Callers run it on
/// a background GCD queue so the blocking wait never touches the
/// cooperative pool or the main thread.
internal struct SmartCardChannel: CardChannel {
  /// Carries a value across the semaphore boundary; sound because the
  /// semaphore serialises the write before the wait returns.
  private final class Box<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
      self.value = value
    }
  }

  /// A reader hands back exactly the bytes the card produced, so a
  /// chunked read may ask for the plain chunk.
  internal var readChunkLength: ReadChunkLength {
    .plain
  }

  private let smartCard: TKSmartCard

  internal init(_ smartCard: TKSmartCard) {
    self.smartCard = smartCard
  }

  /// Sends one command and waits for the card, tracing the exchange.
  ///
  /// The app's own card work -- priming, above all -- was invisible while
  /// only the extensions were traced, which meant a failed hold could be
  /// read about afterwards but never diagnosed. Instruction byte, sizes,
  /// status word and timing only; `VERIFY` is redacted wholesale by
  /// ``CardExchangeTrace``, so no PIN reaches the buffer.
  internal func transmit(_ payload: Data) throws -> Data {
    let reply = Box<Data?>(nil)
    let semaphore = DispatchSemaphore(value: 0)
    let started = ContinuousClock.now
    smartCard.transmit(payload) { response, _ in
      reply.value = response
      semaphore.signal()
    }
    semaphore.wait()
    let elapsed = started.duration(to: ContinuousClock.now)
    ExtensionTrace.append(
      CardExchangeTrace.line(request: payload, response: reply.value, elapsed: elapsed)
    )
    guard let response = reply.value else {
      throw CardOperationError.malformedResponse
    }
    return response
  }

  /// Opens an exclusive session, runs `body`, and ends it - synchronously.
  internal func withSession<T>(_ body: (Self) throws -> T) throws -> T {
    let began = Box(false)
    let failure = Box<Error?>(nil)
    let semaphore = DispatchSemaphore(value: 0)
    smartCard.beginSession { opened, error in
      began.value = opened
      failure.value = error
      semaphore.signal()
    }
    semaphore.wait()
    guard began.value else {
      throw failure.value ?? CardOperationError.sessionUnavailable
    }
    defer { smartCard.endSession() }
    return try body(self)
  }
}
