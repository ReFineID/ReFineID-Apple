// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Observation

/// Whether a smart card is physically in a reader right now.
///
/// Slot state is the reader's answer, read without opening any
/// session - no card I/O, nothing held, nothing another process
/// could be made to wait for. It is a different fact from the
/// token's publication: a present card can lack its token, which
/// is exactly the state the login row has to name. What this fact
/// gates is the offering of card work at all - signing a document
/// and managing PINs are not meaningful without a card under them.
@MainActor
@Observable
internal final class CardPresence {
  internal static let shared = CardPresence()

  /// Whether any slot reports a card, responsive or not.
  internal private(set) var isCardPresent = false

  /// Whether a card is present in an external reader rather than the
  /// iPhone's temporary NFC slot.
  internal private(set) var isReaderCardPresent = false

  /// Whether an external-reader card has completed system probing and
  /// is ready for a session.
  ///
  /// Presence becomes true earlier, while the slot is still `.probing`;
  /// card I/O must wait for this separate fact.
  internal private(set) var isReaderCardReady = false

  /// Whether the first live slot inventory has replaced presentation
  /// hints supplied by the view that opened card management.
  internal private(set) var hasCompletedInitialScan = false

  /// Whether any of those cards is on a contactless interface.
  ///
  /// Read from the slot's synthesized answer to reset, so it costs
  /// no card I/O and is known the moment the card lands on the
  /// antenna. Only this certainty makes the access-number entry
  /// appear: a contact card never needs one.
  internal private(set) var isContactlessCardPresent = false

  /// The slots being watched, by name.
  @ObservationIgnored private var slots: [String: TKSmartCardSlot] = [:]

  /// The reader-list observation, alive for the app's lifetime.
  @ObservationIgnored private var namesObservation: NSKeyValueObservation?

  /// Per-slot state observations, keyed like `slots`.
  @ObservationIgnored private var stateObservations: [String: NSKeyValueObservation] = [:]

  private init() {
    guard let manager = TKSmartCardSlotManager.default else { return }
    namesObservation = manager.observe(\.slotNames, options: [.initial]) {
      [weak self] _, _ in
      Task { @MainActor [weak self] in
        self?.watchSlots()
      }
    }
  }

  /// Follows the reader list: watch every slot, forget the gone.
  private func watchSlots() {
    guard let manager = TKSmartCardSlotManager.default else { return }
    let names = Set(manager.slotNames)
    slots = slots.filter { names.contains($0.key) }
    stateObservations = stateObservations.filter { names.contains($0.key) }
    for name in names where slots[name] == nil {
      guard let slot = manager.slotNamed(name) else { continue }
      watch(slot, named: name)
    }
    recount()
    if !hasCompletedInitialScan {
      hasCompletedInitialScan = true
    }
  }

  /// Watches one slot's card state.
  private func watch(_ slot: TKSmartCardSlot, named name: String) {
    slots[name] = slot
    stateObservations[name] = slot.observe(\.state, options: [.initial]) {
      [weak self] _, _ in
      Task { @MainActor [weak self] in
        self?.recount()
      }
    }
    recount()
  }

  /// A card is present when any slot says anything but "empty".
  ///
  /// A mute card counts: it is physically there, and "insert your
  /// card" would be the wrong thing to tell its holder.
  private func recount() {
    // Assigned only when it differs. Observation notifies on
    // every write, unchanged or not, and each notification
    // re-renders the window that reads this.
    let occupied = slots.filter { _, slot in
      switch slot.state {
      case .validCard, .muteCard, .probing:
        true
      default:
        false
      }
    }
    let present = !occupied.isEmpty
    let readerPresent = occupied.contains { name, _ in
      CardTransport.transport(forSlotNamed: name) == .reader
    }
    let readerReady = slots.contains { name, slot in
      CardTransport.transport(forSlotNamed: name) == .reader
        && slot.state == .validCard
    }
    let contactless = occupied.values.contains { slot in
      slot.atr.map { AnswerToReset.indicatesContactlessInterface(bytes: $0.bytes) } ?? false
    }
    if present != isCardPresent {
      isCardPresent = present
    }
    if contactless != isContactlessCardPresent {
      isContactlessCardPresent = contactless
    }
    if readerPresent != isReaderCardPresent {
      isReaderCardPresent = readerPresent
    }
    if readerReady != isReaderCardReady {
      isReaderCardReady = readerReady
    }
  }
}
