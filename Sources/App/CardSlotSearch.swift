import CryptoTokenKit

/// Finds the slot a card is actually in.
///
/// "The first slot" is not the card's slot. A dual-interface reader
/// publishes its contact, contactless and SAM interfaces as three slots
/// whose names differ only by a trailing index, and the order they are
/// named in is not the order they are used in. Taking the first name is
/// how a card resting on the antenna came to be reported as an empty
/// reader on the status screen, and how a probe answered "no reader or
/// card" about a card that was signing for Safari at the time.
internal enum CardSlotSearch {
  /// The first slot holding a card, with the name it is known by.
  internal static func occupied(
    in manager: TKSmartCardSlotManager
  ) async -> (name: String, slot: TKSmartCardSlot)? {
    for name in manager.slotNames {
      if let slot = await manager.getSlot(withName: name), slot.state == .validCard {
        return (name, slot)
      }
    }
    return nil
  }

  /// The slot worth naming on screen: the one holding a card, else the
  /// first the system names, so an empty reader still has a name.
  internal static func nameToReportOn(in manager: TKSmartCardSlotManager) async -> String? {
    await occupied(in: manager)?.name ?? manager.slotNames.first
  }
}
