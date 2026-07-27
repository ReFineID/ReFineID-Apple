import Foundation

/// A card session opened while the token was minted and deliberately kept
/// open, so the signature that follows still has a live field to work in.
///
/// Only the system-driven contactless path needs this, and it was bought
/// with a measured failure: `ctkd` owns the built-in contactless slot and
/// ends it about two seconds after the mint, so a `beginSession` issued
/// when the signature finally arrives fails with `TKError -7` - there is
/// no field left to open. Holding the session taken at the mint keeps one
/// live field under the mint, the PACE run and the signature.
///
/// The release is driven by a slot-state observation, which is a
/// `@Sendable` closure, and `Token` is not `Sendable` - so the closure
/// cannot capture the token and captures this box instead.
/// `@unchecked Sendable` is sound because every access goes through the
/// lock: the observation fires on CryptoTokenKit's queue while a
/// signature runs on the session's.
///
/// Provenance: `Token.HeldSession` in the donor
/// `platform/apple/RefineIDTokenExtension/Token.swift`, whose held value
/// was that implementation's Rust-FFI relay.
internal final class HeldCardSession: @unchecked Sendable {
  /// Serialises the two queues that reach the held channel.
  private let lock = NSLock()

  /// The channel whose session is being held, or nil once released.
  private var channel: SmartCardChannel?

  /// The held channel, or nil when none is held.
  internal var current: SmartCardChannel? {
    lock.lock()
    defer { lock.unlock() }
    return channel
  }

  /// Takes ownership of `channel`, whose session is already open.
  internal func retain(_ channel: SmartCardChannel) {
    lock.lock()
    defer { lock.unlock() }
    self.channel = channel
  }

  /// Ends and forgets the held session; safe to call repeatedly.
  ///
  /// Call this only when the slot reports the card genuinely `.missing`.
  /// Releasing on any other state was measured tearing down a signature
  /// part way through a read - a card momentarily out of the field is
  /// still the same card.
  internal func release() {
    lock.lock()
    let outgoing = channel
    channel = nil
    lock.unlock()
    outgoing?.endSession()
  }
}
