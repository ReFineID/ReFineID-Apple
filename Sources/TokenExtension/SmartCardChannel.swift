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

  /// Decides which side is responsible for a session that arrives after
  /// the waiter has given up, and hands it back when that is nobody.
  ///
  /// Both sides need the same answer and they run on different threads:
  /// the waiter times out, the callback fires a moment later, and if
  /// neither claims the session it stays open forever -- the card held
  /// by a process no longer interested in it, which is precisely the jam
  /// this timeout exists to end.
  ///
  /// `@unchecked Sendable` is the audit, not a shrug: the flag is only
  /// read and written under the lock, and the card is touched on exactly
  /// one path, to end a session the waiter has already walked away from.
  private final class SessionWait: @unchecked Sendable {
    private let lock = NSLock()
    private let card: TKSmartCard
    private var waiterGaveUp = false

    init(card: TKSmartCard) {
      self.card = card
    }

    /// Called by the waiter when its budget runs out.
    func giveUp() {
      lock.lock()
      waiterGaveUp = true
      lock.unlock()
    }

    /// Called by the callback: ends a session nobody is waiting for.
    func releaseIfAbandoned(opened: Bool) {
      lock.lock()
      let abandoned = waiterGaveUp
      lock.unlock()
      guard opened, abandoned else { return }
      card.endSession()
    }
  }

  /// How long to wait for whoever else has the card.
  ///
  /// The wait used to be unbounded, and an unbounded wait is how one
  /// stuck process takes the card away from everything else: the app
  /// froze rather than saying the card was busy. Eight seconds is far
  /// longer than any operation here -- a handshake is about a second, a
  /// signature about the same -- so a legitimate queue still clears,
  /// while a holder that is never letting go becomes an error instead of
  /// a hang.
  private static let sessionWaitSeconds: Int = 8

  /// The same budget, in the units `DispatchSemaphore` wants.
  private static let sessionWaitBudget: DispatchTimeInterval = .seconds(sessionWaitSeconds)

  /// A reader hands back exactly the bytes the card produced, so a
  /// chunked read may ask for the plain chunk.
  internal var readChunkLength: ReadChunkLength {
    .plain
  }

  private let smartCard: TKSmartCard

  internal init(_ smartCard: TKSmartCard) {
    self.smartCard = smartCard
  }

  /// Sends one APDU, and records what it was and what it cost.
  ///
  /// This is the one place every exchange the extension makes passes
  /// through -- plain and secure-messaged alike, since the secure channel
  /// wraps this one -- so it is where the trace is taken. The recorded
  /// line carries the instruction, the sizes, the status word and the
  /// elapsed time, never a payload, and VERIFY is redacted wholesale
  /// (``CardExchangeTrace``).
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
    TokenLog.trace(
      CardExchangeTrace.line(request: payload, response: reply.value, elapsed: elapsed)
    )
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
    let wait = SessionWait(card: smartCard)
    let semaphore = DispatchSemaphore(value: 0)
    let started = ContinuousClock.now
    smartCard.beginSession { opened, error in
      began.value = opened
      failure.value = error
      wait.releaseIfAbandoned(opened: opened)
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + Self.sessionWaitBudget) == .success else {
      wait.giveUp()
      TokenLog.trace(
        "session: gave up waiting after "
          + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now)) + " ms"
      )
      throw CardOperationError.sessionUnavailable
    }
    let elapsed = TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
    guard began.value else {
      // The failure is the diagnosis here: TKError -7 on the built-in
      // contactless slot means the field the mint held has already ended.
      TokenLog.trace(
        "session: begin refused ms=\(elapsed) reason=\(String(describing: failure.value))"
      )
      throw failure.value ?? CardOperationError.sessionUnavailable
    }
    TokenLog.trace("session: begin ok ms=\(elapsed)")
  }

  /// Ends a session opened with ``beginSession()``.
  internal func endSession() {
    TokenLog.trace("session: end")
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
