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
  /// Shorter than the driver's budget on purpose. This is the status
  /// screen: a card that is busy signing for Safari should make a row
  /// say so, not make the app stop answering.
  private static let sessionWaitSeconds: Int = 4

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
    AppTrace.append(
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
    let wait = SessionWait(card: smartCard)
    let semaphore = DispatchSemaphore(value: 0)
    smartCard.beginSession { opened, error in
      began.value = opened
      failure.value = error
      wait.releaseIfAbandoned(opened: opened)
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + Self.sessionWaitBudget) == .success else {
      wait.giveUp()
      throw CardOperationError.sessionUnavailable
    }
    guard began.value else {
      throw failure.value ?? CardOperationError.sessionUnavailable
    }
    defer { smartCard.endSession() }
    return try body(self)
  }
}
