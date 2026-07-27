import CardCore
import CryptoTokenKit
import Foundation

/// Adapts a `TKSmartCard` to CardCore's synchronous `CardChannel`, and
/// opens the exclusive session the card work runs inside.
///
/// The CTK token/session entry points are synchronous and run on ctkd's
/// own threads; the card is a synchronous blocking device. So each APDU is
/// driven with a completion handler plus a `DispatchSemaphore` - the reply
/// fires on `TKSmartCard`'s own queue and signals the wait - and never
/// through Swift concurrency. Blocking the ctkd thread this way is safe
/// and is what the proven reference does; an async/await bridge on that
/// thread is not (it hangs the sign, looping the PIN prompt).
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

  internal func transmit(_ payload: Data) throws -> Data {
    let reply = Box<Data?>(nil)
    let semaphore = DispatchSemaphore(value: 0)
    smartCard.transmit(payload) { response, _ in
      reply.value = response
      semaphore.signal()
    }
    semaphore.wait()
    guard let response = reply.value else {
      throw CardOperationError.malformedResponse
    }
    return response
  }

  /// Opens an exclusive session and LEAVES IT OPEN, for the caller to end.
  ///
  /// A session is not optional anywhere: `getSmartCard()` does not
  /// guarantee an open one, `transmit` is legal only inside one, and a
  /// sessionless transmit on the built-in contactless slot is parked by
  /// `ctkd` forever - no error, no timeout. `beginSession`'s callback
  /// fires on `TKSmartCard`'s own queue, so the semaphore never
  /// deadlocks.
  ///
  /// The caller owns the session from here and must end it. Most callers
  /// want ``withSession(_:)``; the exception is the contactless mint,
  /// which keeps its session alive for the signature that follows (see
  /// ``HeldCardSession``).
  internal func beginSession() throws {
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
  }

  /// Ends a session opened with ``beginSession()``.
  internal func endSession() {
    smartCard.endSession()
  }

  /// Opens an exclusive session, runs `body`, and ends the session - all
  /// synchronously.
  ///
  /// Required on both the createToken and the contact sign paths (the
  /// reference opens a session on every sign, proven by its success
  /// trace).
  internal func withSession<T>(_ body: (Self) throws -> T) throws -> T {
    try beginSession()
    defer { endSession() }
    return try body(self)
  }
}
