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

  /// Opens an exclusive session, runs `body`, and ends the session - all
  /// synchronously.
  ///
  /// Required on both the createToken and the sign paths: `getSmartCard()`
  /// does not guarantee an open session and `transmit` is legal only
  /// inside one (the reference opens a session on every sign, proven by
  /// its success trace). `beginSession`'s callback fires on `TKSmartCard`'s
  /// queue, so the semaphore never deadlocks.
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
