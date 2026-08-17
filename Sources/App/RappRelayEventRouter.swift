// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Re-targetable sink for relay events.
///
/// A relay session captures its event closure at creation, but the live
/// pairing channel outlives the pairing UI that dialed it. Routing events
/// through this indirection lets the adopter install its own sink without
/// rebuilding the connection.
internal final class RappRelayEventRouter<Event: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var sink: @Sendable (Event) -> Void

  internal init(_ initial: @escaping @Sendable (Event) -> Void) {
    sink = initial
  }

  /// Replaces the sink; events already delivered are unaffected.
  internal func install(_ replacement: @escaping @Sendable (Event) -> Void) {
    lock.lock()
    sink = replacement
    lock.unlock()
  }

  /// Delivers one event to the current sink.
  internal func route(_ event: Event) {
    lock.lock()
    let current = sink
    lock.unlock()
    current(event)
  }
}
